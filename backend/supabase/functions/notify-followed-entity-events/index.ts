// Setzt die in notify-changes/index.ts als "architektonisch ein anderer
// Baustein" zurückgestellte "followed_ensemble_new_event"-Benachrichtigung
// um — erweitert um Personen und Venues (Nutzerwunsch: "bestimmten
// Ensembles/Personen/Venues folgen ... Ankündigung, wenn neues Konzert dazu
// kommt"). Anders als notify-changes (reagiert auf ÄNDERUNGEN an bereits
// favorisierten Events) matcht diese Funktion NEU angelegte Events gegen
// die Interessen-/Follow-Tabellen (user_favorite_persons/_ensembles/
// _venues) — dieselben Tabellen, die die native App für den "Folgen"-Button
// und die personalisierten Home-Reihen nutzt (siehe
// ios-native/KlangradarNative/Core/Repositories/UserRepository.swift:
// FollowStore).
//
// Ein Event kann mehrere Treffer liefern (z.B. Venue UND Ensemble gefolgt) —
// pro Nutzer trotzdem nur EINE Push (notification_log dedupliziert auf
// user_id+event_id+notification_type, "followed_entity_new_event").
//
// Nutzt bewusst dieselbe notification_preferences-Spalte
// "followed_ensemble_new_event" für alle drei Entitätstypen (kein Schema-
// Umbau nötig) — die Profil-UI-Beschriftung wurde entsprechend verallgemeinert.
//
// Aufruf: POST {} — läuft per Cron (siehe run_notify_followed_entity_events()
// Migration), verarbeitet events der letzten 3 Tage (gleiches Zeitfenster
// wie notify-changes), maximal 200 pro Lauf.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPushToTokens } from "../_shared/fcm.ts";

interface NewEventRow {
  id: string;
  slug: string;
  title: string;
  created_at: string;
  venue_id: string | null;
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
  const { data: events, error: fetchError } = await supabase
    .from("events")
    .select("id, slug, title, created_at, venue_id")
    .eq("status", "scheduled")
    .neq("review_status", "rejected")
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(200)
    .returns<NewEventRow[]>();

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 });
  }
  if (!events || events.length === 0) {
    return new Response(JSON.stringify({ processed: 0, message: "Keine neuen Events." }));
  }

  let notified = 0;
  let skippedPreference = 0;
  let skippedNoToken = 0;
  let invalidTokensRemoved = 0;
  const errors: string[] = [];

  for (const event of events) {
    try {
      const { data: participantRows } = await supabase
        .from("event_participants")
        .select("person_id, ensemble_id")
        .eq("event_id", event.id);
      const personIDs = (participantRows ?? []).map((r) => r.person_id).filter((v): v is string => !!v);
      const ensembleIDs = (participantRows ?? []).map((r) => r.ensemble_id).filter((v): v is string => !!v);

      // Alle Nutzer sammeln, die MINDESTENS eine der beteiligten Entitäten
      // folgen UND für diese konkrete Entität Benachrichtigungen nicht
      // abgeschaltet haben (notify_new_events, siehe
      // 20261016000010_follow_per_entity_notifications.sql) — Set statt
      // Array, ein Nutzer soll pro Event nur einmal benachrichtigt werden,
      // auch wenn er z.B. Venue UND Solist:in folgt.
      const followerIDs = new Set<string>();

      if (event.venue_id) {
        const { data } = await supabase
          .from("user_favorite_venues")
          .select("user_id")
          .eq("venue_id", event.venue_id)
          .eq("notify_new_events", true);
        for (const row of data ?? []) followerIDs.add(row.user_id as string);
      }
      if (personIDs.length > 0) {
        const { data } = await supabase
          .from("user_favorite_persons")
          .select("user_id")
          .in("person_id", personIDs)
          .eq("notify_new_events", true);
        for (const row of data ?? []) followerIDs.add(row.user_id as string);
      }
      if (ensembleIDs.length > 0) {
        const { data } = await supabase
          .from("user_favorite_ensembles")
          .select("user_id")
          .in("ensemble_id", ensembleIDs)
          .eq("notify_new_events", true);
        for (const row of data ?? []) followerIDs.add(row.user_id as string);
      }

      if (followerIDs.size === 0) continue;

      for (const userID of followerIDs) {
        const { data: alreadySent } = await supabase
          .from("notification_log")
          .select("id")
          .eq("user_id", userID)
          .eq("event_id", event.id)
          .eq("notification_type", "followed_entity_new_event")
          .maybeSingle();
        if (alreadySent) continue;

        const { data: prefs } = await supabase
          .from("notification_preferences")
          .select("followed_ensemble_new_event")
          .eq("user_id", userID)
          .maybeSingle();
        if (prefs?.followed_ensemble_new_event === false) {
          skippedPreference++;
          continue;
        }

        const { data: tokenRows } = await supabase
          .from("push_tokens")
          .select("token")
          .eq("user_id", userID);
        const tokens = (tokenRows ?? []).map((t) => t.token as string);
        if (tokens.length === 0) {
          skippedNoToken++;
          continue;
        }

        const results = await sendPushToTokens(tokens, {
          title: "Neues Konzert",
          body: `${event.title} — jetzt in deinem Radar.`,
          data: { route: `/event/${event.slug}` },
        });
        const invalidTokens = results.filter((r) => r.invalidToken).map((r) => r.token);
        if (invalidTokens.length > 0) {
          await supabase.from("push_tokens").delete().in("token", invalidTokens);
          invalidTokensRemoved += invalidTokens.length;
        }

        await supabase.from("notification_log").insert({
          user_id: userID,
          event_id: event.id,
          notification_type: "followed_entity_new_event",
        });
        if (results.some((r) => r.ok)) notified++;
      }
    } catch (err) {
      errors.push(`event ${event.id}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      eventsProcessed: events.length,
      notified,
      skippedPreference,
      skippedNoToken,
      invalidTokensRemoved,
      errorCount: errors.length,
      errors: errors.slice(0, 10),
    }),
  );
});
