// Erstellt von Claude Code. Verschickt Social-Benachrichtigungen aus
// social_notifications (Freundschaftsanfragen, Konzertpläne, geteilte
// Listen, "X geht auch hin"). Ausgelöst von notify_social() per pg_net,
// arbeitet aber immer alle offenen Einträge ab (robust bei Ausfällen).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { sendPushToTokens } from "../_shared/fcm.ts";
import { socialMessage } from "./messages.ts";

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: rows, error } = await db
    .from("social_notifications")
    .select("id, kind, recipient, actor, event_id, ref_id")
    .is("sent_at", null)
    .order("created_at")
    .limit(100);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  let sent = 0;
  for (const row of rows ?? []) {
    // Sofort als verarbeitet markieren, damit parallele Aufrufe nicht doppelt senden.
    const { data: claimed } = await db.from("social_notifications").update({ sent_at: new Date().toISOString() }).eq("id", row.id).is("sent_at", null).select("id");
    if (!claimed?.length) continue;

    const [{ data: actor }, { data: event }, { data: list }, { data: tokens }] = await Promise.all([
      row.actor ? db.from("profiles").select("display_name").eq("id", row.actor).maybeSingle() : Promise.resolve({ data: null }),
      row.event_id ? db.from("events").select("title, slug").eq("id", row.event_id).maybeSingle() : Promise.resolve({ data: null }),
      row.kind === "list_shared" && row.ref_id ? db.from("favorite_lists").select("name").eq("id", row.ref_id).maybeSingle() : Promise.resolve({ data: null }),
      db.from("push_tokens").select("token").eq("user_id", row.recipient),
    ]);
    const message = socialMessage({
      kind: row.kind,
      actorName: (actor as { display_name?: string } | null)?.display_name ?? "Ein:e Freund:in",
      eventTitle: (event as { title?: string } | null)?.title,
      eventSlug: (event as { slug?: string } | null)?.slug,
      listName: (list as { name?: string } | null)?.name,
    });
    const tokenList = (tokens ?? []).map((t: { token: string }) => t.token);
    if (!message || tokenList.length === 0) continue;
    const results = await sendPushToTokens(tokenList, { title: message.title, body: message.body, data: { route: message.route } });
    const invalid = results.filter((r) => r.invalidToken).map((r) => r.token);
    if (invalid.length) await db.from("push_tokens").delete().in("token", invalid);
    sent++;
  }
  return new Response(JSON.stringify({ processed: rows?.length ?? 0, sent }), { headers: { "Content-Type": "application/json" } });
});
