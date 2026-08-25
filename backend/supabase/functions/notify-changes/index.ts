// Zweite Push-Benachrichtigungsart (Task #15, Fortsetzung von
// notify-reminders/index.ts): Preisänderung, fast ausverkauft, Absage/
// Verschiebung — für Nutzer mit einem Favoriten-Eintrag auf dem betroffenen
// Event. Speist sich aus event_changes (Trigger log_event_changes,
// Migrationen 20261002000011/…14), das unabhängig vom Schreibpfad jede
// relevante Änderung protokolliert.
//
// "new_matching_events" und "followed_ensemble_new_event" (die anderen
// beiden notification_preferences-Spalten) sind bewusst NICHT Teil dieser
// Funktion — beide brauchen ein Matching NEUER Events gegen Nutzerprofile/
// Favoriten statt eine Änderung an einem bereits favorisierten Event,
// architektonisch ein anderer Baustein. Siehe Erweiterungsplan.
//
// Aufruf: POST {} — läuft per Cron, verarbeitet event_changes der letzten 3
// Tage (begrenzt, damit ein Ausfall des Crons nicht Monate alter Änderungen
// auf einmal nachfeuert), maximal 200 pro Lauf. notification_log verhindert
// Doppelversand pro (Nutzer, Event, Anlass).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPushToTokens } from "../_shared/fcm.ts";

interface EventChangeRow {
  id: number;
  event_id: string;
  field_name: string;
  old_value: string | null;
  new_value: string | null;
  changed_at: string;
}

const STATUS_LABEL: Record<string, string> = {
  cancelled: "abgesagt",
  postponed: "verschoben",
};

/** Anlass + Push-Text für eine event_changes-Zeile, oder null wenn diese
 * Zeile (noch) keinen eigenen Push wert ist (z.B. eine Statusänderung ohne
 * Absage/Verschiebung — der Trigger loggt jede Statusänderung, nicht jede
 * ist push-würdig). */
function notificationFor(
  change: EventChangeRow,
  eventTitle: string,
): { type: string; prefsColumn: "price_changes" | "almost_sold_out" | null; title: string; body: string } | null {
  switch (change.field_name) {
    case "price":
      return {
        type: "price_changed",
        prefsColumn: "price_changes",
        title: eventTitle,
        body: "Der Preis hat sich geändert.",
      };
    case "remaining_tickets_status":
      return {
        type: "almost_sold_out",
        prefsColumn: "almost_sold_out",
        title: eventTitle,
        body: change.new_value === "sold_out" ? "Jetzt ausverkauft." : "Nur noch wenige Tickets verfügbar.",
      };
    case "status": {
      const label = change.new_value ? STATUS_LABEL[change.new_value] : undefined;
      if (!label) return null; // andere Statuswechsel (z.B. interne Korrekturen) sind kein Push wert
      return {
        type: "status_changed",
        // Kritische Information (Absage/Verschiebung) — keine eigene
        // notification_preferences-Spalte, wird nicht durch ein Opt-out
        // unterdrückt (siehe docs/06-mvp-plan.md: "kritische Änderungen").
        prefsColumn: null,
        title: eventTitle,
        body: `Die Veranstaltung wurde ${label}.`,
      };
    }
    default:
      return null;
  }
}

import { requireInternalAuth } from "../_shared/internalAuth.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Nur POST" }), { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const since = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();
  const { data: changes, error: fetchError } = await supabase
    .from("event_changes")
    .select("id, event_id, field_name, old_value, new_value, changed_at")
    .in("field_name", ["price", "remaining_tickets_status", "status"])
    .gte("changed_at", since)
    .order("changed_at", { ascending: false })
    .limit(200)
    .returns<EventChangeRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!changes || changes.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine relevanten Änderungen." }));
  }

  let notified = 0;
  let skippedPreference = 0;
  let skippedNoToken = 0;
  let invalidTokensRemoved = 0;
  const errors: string[] = [];

  for (const change of changes) {
    try {
      const { data: event } = await supabase
        .from("events")
        .select("title, slug")
        .eq("id", change.event_id)
        .maybeSingle();
      if (!event) continue;

      const notification = notificationFor(change, event.title as string);
      if (!notification) continue;

      const { data: favoriteRows } = await supabase
        .from("favorites")
        .select("user_id")
        .eq("event_id", change.event_id);
      if (!favoriteRows || favoriteRows.length === 0) continue;

      for (const fav of favoriteRows) {
        const { data: alreadySent } = await supabase
          .from("notification_log")
          .select("id")
          .eq("user_id", fav.user_id)
          .eq("event_id", change.event_id)
          .eq("notification_type", notification.type)
          .maybeSingle();
        if (alreadySent) continue;

        if (notification.prefsColumn) {
          const { data: prefs } = await supabase
            .from("notification_preferences")
            .select(notification.prefsColumn)
            .eq("user_id", fav.user_id)
            .maybeSingle();
          const prefsRecord = prefs as Record<string, boolean> | null;
          if (prefsRecord?.[notification.prefsColumn] === false) {
            skippedPreference++;
            continue;
          }
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

        const results = await sendPushToTokens(tokens, {
          title: notification.title,
          body: notification.body,
          data: { route: `/event/${event.slug}` },
        });
        const invalidTokens = results.filter((r) => r.invalidToken).map((r) => r.token);
        if (invalidTokens.length > 0) {
          await supabase.from("push_tokens").delete().in("token", invalidTokens);
          invalidTokensRemoved += invalidTokens.length;
        }

        await supabase.from("notification_log").insert({
          user_id: fav.user_id,
          event_id: change.event_id,
          notification_type: notification.type,
        });
        if (results.some((r) => r.ok)) notified++;
      }
    } catch (err) {
      errors.push(`change ${change.id}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      changesProcessed: changes.length,
      notified,
      skippedPreference,
      skippedNoToken,
      invalidTokensRemoved,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
