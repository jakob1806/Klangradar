// Erste konkrete Umsetzung von Phase A.1 (docs/09-feature-expansion-plan.md):
// "Erinnerung morgen" für favorisierte Veranstaltungen — der einfachste der
// fünf in notification_preferences vorgesehenen Anlässe (kein Vorher/Nachher-
// Vergleich nötig wie bei Preisänderung/fast ausverkauft, nur reines
// Datums-Fenster). Die anderen vier Anlässe (new_matching_events,
// price_changes, almost_sold_out, followed_ensemble_new_event) sind bewusst
// NICHT Teil dieser Funktion — jeder braucht eine eigene Änderungserkennung
// und folgt als eigener Ausbauschritt, siehe Plan-Dokument.
//
// Aufruf: POST {} (keine Parameter) — läuft einmal täglich per Cron, findet
// alle Favoriten mit Start morgen (00:00–23:59 des Folgetags), sendet je
// Nutzer maximal eine Erinnerung, respektiert notification_preferences und
// überspringt Nutzer ohne bestätigten Push-Token. notification_log
// verhindert Doppelversand bei mehrfachem Lauf.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPushToTokens, verifyFcmCredentials } from "../_shared/fcm.ts";

const NOTIFICATION_TYPE = "reminder_day_before";

interface FavoriteRow {
  user_id: string;
  events: { id: string; title: string; slug: string; start_datetime: string } | null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Nur POST" }), { status: 405 });
  }

  let body: { verifyOnly?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  // Reiner Zugangsdaten-Check ohne echte Nutzer/Favoriten nötig — zum
  // Prüfen direkt nach dem Setzen von FCM_SERVICE_ACCOUNT_JSON, solange es
  // noch keine echten Push-Tokens in der DB gibt.
  if (body.verifyOnly === true) {
    const result = await verifyFcmCredentials();
    return new Response(JSON.stringify(result), { status: result.ok ? 200 : 500 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const now = new Date();
  const tomorrowStart = new Date(now);
  tomorrowStart.setUTCDate(tomorrowStart.getUTCDate() + 1);
  tomorrowStart.setUTCHours(0, 0, 0, 0);
  const tomorrowEnd = new Date(tomorrowStart);
  tomorrowEnd.setUTCHours(23, 59, 59, 999);

  const { data: favorites, error: fetchError } = await supabase
    .from("favorites")
    .select("user_id, events(id, title, slug, start_datetime)")
    .gte("events.start_datetime", tomorrowStart.toISOString())
    .lte("events.start_datetime", tomorrowEnd.toISOString())
    .returns<FavoriteRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  // Der events-Join filtert oben nicht das äußere Ergebnis (PostgREST
  // wendet .gte/.lte auf embedded resources als Filter an, liefert aber bei
  // Nichttreffer eine Zeile mit events: null statt die Zeile wegzulassen) —
  // deshalb hier zusätzlich explizit auf vorhandenes events-Objekt filtern.
  const relevant = (favorites ?? []).filter((f) => f.events !== null);

  let notified = 0;
  let skippedNoToken = 0;
  let skippedPreference = 0;
  const errors: string[] = [];
  let invalidTokensRemoved = 0;

  for (const fav of relevant) {
    const event = fav.events!;
    try {
      const { data: alreadySent } = await supabase
        .from("notification_log")
        .select("id")
        .eq("user_id", fav.user_id)
        .eq("event_id", event.id)
        .eq("notification_type", NOTIFICATION_TYPE)
        .maybeSingle();
      if (alreadySent) continue;

      const { data: prefs } = await supabase
        .from("notification_preferences")
        .select("reminder_day_before")
        .eq("user_id", fav.user_id)
        .maybeSingle();
      // Kein Zeile = Default (siehe notification_preferences_providers.dart:
      // "vor dem ersten Toggle einfach noch keine Zeile") — Default ist true.
      if (prefs?.reminder_day_before === false) {
        skippedPreference++;
        continue;
      }

      const { data: tokenRows } = await supabase
        .from("push_tokens")
        .select("token")
        .eq("user_id", fav.user_id);
      const tokens = (tokenRows ?? []).map((t) => t.token as string);
      if (tokens.length === 0) {
        skippedNoToken++;
        continue;
      }

      const start = new Date(event.start_datetime);
      const time = `${start.getUTCHours().toString().padStart(2, "0")}:${
        start.getUTCMinutes().toString().padStart(2, "0")
      }`;
      const results = await sendPushToTokens(tokens, {
        title: "Morgen: " + event.title,
        body: `Um ${time} Uhr — nicht vergessen!`,
        data: { route: `/event/${event.slug}` },
      });

      const invalidTokens = results.filter((r) => r.invalidToken).map((r) => r.token);
      if (invalidTokens.length > 0) {
        await supabase.from("push_tokens").delete().in("token", invalidTokens);
        invalidTokensRemoved += invalidTokens.length;
      }

      // Als versendet markieren, sobald MINDESTENS EIN Token erfolgreich war
      // ODER kein Token mehr übrig ist, nachdem ungültige entfernt wurden —
      // sonst würde ein Nutzer mit ausschließlich toten Tokens jeden Tag neu
      // versucht.
      const anySuccess = results.some((r) => r.ok);
      await supabase.from("notification_log").insert({
        user_id: fav.user_id,
        event_id: event.id,
        notification_type: NOTIFICATION_TYPE,
      });
      if (anySuccess) notified++;
    } catch (err) {
      errors.push(`user ${fav.user_id} / event ${event.id}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      candidates: relevant.length,
      notified,
      skippedNoToken,
      skippedPreference,
      invalidTokensRemoved,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
