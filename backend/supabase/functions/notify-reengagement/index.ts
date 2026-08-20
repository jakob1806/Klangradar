// Re-Engagement-Push für inaktive Nutzer (Discovery & Engagement,
// Nutzeranfrage: "Nutzer gezielt auf interessante neue Inhalte
// zurückbringen"). Nutzt die bislang ungenutzte notification_preferences-
// Spalte "new_matching_events" (siehe notify-changes/index.ts: dort explizit
// als "architektonisch ein anderer Baustein" zurückgestellt — das hier ist
// dieser Baustein).
//
// "Inaktiv" = seit mindestens 14 Tagen keine home_feed_impressions-Zeile
// mehr (wird bei jedem Home-Laden für Hero + "Für dich" geschrieben, siehe
// app/lib/features/home/application/home_providers.dart) UND das Konto ist
// mindestens 14 Tage alt (neue Nutzer, die die App einfach noch nicht
// geöffnet haben, sollen nicht sofort als "inaktiv" markiert werden).
//
// Empfehlung pro Nutzer: ein bevorstehendes Event an einer gefolgten Venue/
// Person/Ensemble (dieselben user_favorite_*-Tabellen wie überall sonst);
// ohne Treffer ein gemeinsamer Fallback (das Event mit den meisten
// Favoriten insgesamt) — wird einmal pro Lauf ermittelt, nicht pro Nutzer.
//
// notification_log dedupliziert wie bei den anderen notify-*-Funktionen auf
// (Nutzer, Event, Typ); zusätzlich ein expliziter 14-Tage-Cooldown über
// notification_type='reengagement', damit ein Nutzer nicht bei jedem Lauf
// (täglich) erneut angestoßen wird, nur weil beim nächsten Mal ein anderes
// Event vorgeschlagen würde.
//
// Aufruf: POST {} — läuft täglich per Cron (run_notify_reengagement()),
// maximal 200 Nutzer pro Lauf.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPushToTokens } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Nur POST" }), { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const inactiveSince = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString();
  const cooldownSince = inactiveSince;

  const { data: recentlyActive, error: activeError } = await supabase
    .from("home_feed_impressions")
    .select("user_id")
    .gte("shown_at", inactiveSince);
  if (activeError) {
    return new Response(JSON.stringify({ error: activeError.message }), { status: 500 });
  }
  const activeUserIds = new Set((recentlyActive ?? []).map((r) => r.user_id as string));

  const { data: recentlyNotified, error: notifiedError } = await supabase
    .from("notification_log")
    .select("user_id")
    .eq("notification_type", "reengagement")
    .gte("sent_at", cooldownSince);
  if (notifiedError) {
    return new Response(JSON.stringify({ error: notifiedError.message }), { status: 500 });
  }
  const recentlyNotifiedIds = new Set((recentlyNotified ?? []).map((r) => r.user_id as string));

  const { data: candidates, error: candidatesError } = await supabase
    .from("profiles")
    .select("id, created_at")
    .lte("created_at", inactiveSince)
    .limit(500);
  if (candidatesError) {
    return new Response(JSON.stringify({ error: candidatesError.message }), { status: 500 });
  }

  const inactiveUserIds = (candidates ?? [])
    .map((c) => c.id as string)
    .filter((id) => !activeUserIds.has(id) && !recentlyNotifiedIds.has(id))
    .slice(0, 200);

  if (inactiveUserIds.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine inaktiven Nutzer." }));
  }

  // Gemeinsamer Fallback für Nutzer ohne persönlichen Treffer — einmal
  // ermittelt statt pro Nutzer neu berechnet.
  const { data: fallbackRows } = await supabase
    .from("favorites")
    .select("event_id, events!inner(id, title, slug, start_datetime, status)")
    .eq("events.status", "scheduled")
    .gte("events.start_datetime", new Date().toISOString());
  const fallbackCounts = new Map<string, { title: string; slug: string; count: number }>();
  for (const row of fallbackRows ?? []) {
    const event = row.events as unknown as { id: string; title: string; slug: string };
    const entry = fallbackCounts.get(event.id) ?? { title: event.title, slug: event.slug, count: 0 };
    entry.count += 1;
    fallbackCounts.set(event.id, entry);
  }
  const fallbackEvent = [...fallbackCounts.entries()].sort((a, b) => b[1].count - a[1].count)[0];
  const fallback = fallbackEvent
    ? { id: fallbackEvent[0], title: fallbackEvent[1].title, slug: fallbackEvent[1].slug }
    : null;

  let notified = 0;
  let skippedPreference = 0;
  let skippedNoMatch = 0;
  let skippedNoToken = 0;
  let invalidTokensRemoved = 0;
  const errors: string[] = [];

  for (const userId of inactiveUserIds) {
    try {
      const { data: prefs } = await supabase
        .from("notification_preferences")
        .select("new_matching_events")
        .eq("user_id", userId)
        .maybeSingle();
      if (prefs && (prefs as Record<string, boolean>).new_matching_events === false) {
        skippedPreference++;
        continue;
      }

      const { data: candidateRows } = await supabase.rpc("reengagement_candidate_event", { p_user_id: userId });
      const candidate = (candidateRows as { id: string; title: string; slug: string }[] | null)?.[0];
      const picked = candidate ?? fallback;

      if (!picked) {
        skippedNoMatch++;
        continue;
      }

      const { data: alreadySent } = await supabase
        .from("notification_log")
        .select("id")
        .eq("user_id", userId)
        .eq("event_id", picked.id)
        .eq("notification_type", "reengagement")
        .maybeSingle();
      if (alreadySent) continue;

      const { data: tokenRows } = await supabase.from("push_tokens").select("token").eq("user_id", userId);
      const tokens = (tokenRows ?? []).map((t) => t.token as string);
      if (tokens.length === 0) {
        skippedNoToken++;
        continue;
      }

      const results = await sendPushToTokens(tokens, {
        title: "Lange nicht gesehen 🎻",
        body: `${picked.title} könnte dir gefallen — schau mal wieder rein.`,
        data: { route: `/event/${picked.slug}` },
      });
      const invalidTokens = results.filter((r) => r.invalidToken).map((r) => r.token);
      if (invalidTokens.length > 0) {
        await supabase.from("push_tokens").delete().in("token", invalidTokens);
        invalidTokensRemoved += invalidTokens.length;
      }

      await supabase.from("notification_log").insert({
        user_id: userId,
        event_id: picked.id,
        notification_type: "reengagement",
      });
      if (results.some((r) => r.ok)) notified++;
    } catch (err) {
      errors.push(`user ${userId}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      processed: inactiveUserIds.length,
      notified,
      skippedPreference,
      skippedNoMatch,
      skippedNoToken,
      invalidTokensRemoved,
      errors: errors.length > 0 ? errors : undefined,
    }),
  );
});
