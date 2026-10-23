// Erstellt von Claude Code. Zentraler Push-Versand (alle 15 Min per Cron):
// Kandidaten (push_candidates) → Auswahl pro Nutzer (select.ts: Budget,
// Ruhezeit, Wunsch-Uhrzeit, Lernrate) → KI-Text mit Prüfung, sonst Vorlage
// (texts.ts) → Versand mit Bild, Kategorie (Schnellaktionen) und Gruppierung
// → push_log. POST {"dryRun": true} zeigt nur die Auswahl samt Texten.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { sendPushToTokens } from "../_shared/fcm.ts";
import { callAiFunction, hasAnyAiProviderConfigured } from "../_shared/ai/router.ts";
import { selectPushes, type Candidate, type UserContext } from "./select.ts";
import { SYSTEM_PROMPT, TEXT_FUNCTION, templateText, userPrompt, validateText, type PushText } from "./texts.ts";

const TRANSACTIONAL = new Set(["concert_day"]);
const CATEGORY: Record<string, string> = {
  new_followed: "EVENT", almost_sold_out: "EVENT", weekly_pick: "EVENT", reengagement: "EVENT",
  concert_day: "CONCERT_DAY", how_was_it: "RATE",
};
const THREAD: Record<string, string> = {
  new_followed: "neu", almost_sold_out: "erinnerungen", concert_day: "erinnerungen",
  how_was_it: "erinnerungen", weekly_pick: "empfehlungen", reengagement: "empfehlungen",
};

async function writeText(c: Candidate, useAi: boolean): Promise<{ text: PushText; author: string }> {
  if (useAi) {
    try {
      const result = await callAiFunction(SYSTEM_PROMPT, userPrompt(c), TEXT_FUNCTION);
      const text = result?.args as PushText | undefined;
      if (text && validateText(text, c)) return { text: { title: text.title.trim(), body: text.body.trim() }, author: `ai:${result!.provider}` };
    } catch (_) {
      // Vorlage übernimmt.
    }
  }
  return { text: templateText(c), author: "template" };
}

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dryRun === true;
  const now = body.now ? new Date(body.now) : new Date();
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const [{ data: candidates, error }, { data: engagement }, { data: hours }, { data: recent }] = await Promise.all([
    db.rpc("push_candidates"),
    db.rpc("push_engagement"),
    db.rpc("push_preferred_hours"),
    db.from("push_log").select("user_id, kind, sent_at").gte("sent_at", new Date(now.getTime() - 7 * 86400000).toISOString()),
  ]);
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

  const contexts = new Map<string, UserContext>();
  const ctxFor = (id: string) => {
    if (!contexts.has(id)) contexts.set(id, { sentLastDay: 0, sentLastWeek: 0, preferredHour: 18, engagement: {} });
    return contexts.get(id)!;
  };
  for (const row of (recent ?? []) as { user_id: string; kind: string; sent_at: string }[]) {
    if (TRANSACTIONAL.has(row.kind)) continue;
    const ctx = ctxFor(row.user_id);
    ctx.sentLastWeek++;
    if (now.getTime() - new Date(row.sent_at).getTime() < 86400000) ctx.sentLastDay++;
  }
  for (const row of (engagement ?? []) as { user_id: string; kind: string; sent: number; opened: number }[]) {
    ctxFor(row.user_id).engagement[row.kind] = { sent: Number(row.sent), opened: Number(row.opened) };
  }
  for (const row of (hours ?? []) as { user_id: string; hour: number }[]) ctxFor(row.user_id).preferredHour = row.hour;

  const chosen = selectPushes((candidates ?? []) as Candidate[], contexts, now);
  const useAi = hasAnyAiProviderConfigured();
  const results: { user: string; kind: string; title: string; body: string; author: string; sent?: boolean }[] = [];

  for (const c of chosen.slice(0, 300)) {
    const { text, author } = await writeText(c, useAi);
    if (dryRun) { results.push({ user: c.user_id, kind: c.kind, ...text, author }); continue; }

    // Erst protokollieren (unique dedupe_key schützt vor Doppelversand), dann senden.
    const { data: log, error: logError } = await db.from("push_log").insert({
      user_id: c.user_id, kind: c.kind, dedupe_key: c.dedupe_key, event_id: c.event_id,
      title: text.title, body: text.body, author, priority: c.priority,
    }).select("id").single();
    if (logError || !log) continue;

    const { data: tokens } = await db.from("push_tokens").select("token").eq("user_id", c.user_id);
    const list = (tokens ?? []).map((t: { token: string }) => t.token);
    const slug = c.facts.slug ?? c.facts.events?.[0]?.slug;
    const sendResults = await sendPushToTokens(list, {
      title: text.title,
      body: text.body,
      category: CATEGORY[c.kind],
      threadId: THREAD[c.kind],
      imageUrl: c.facts.image_url ?? c.facts.events?.[0]?.image_url ?? undefined,
      data: {
        route: slug ? `/event/${slug}` : "/",
        push_log_id: String(log.id),
        ...(c.event_id ? { event_id: c.event_id } : {}),
        ...(slug ? { event_slug: slug } : {}),
        kind: c.kind,
      },
    });
    const invalid = sendResults.filter((r) => r.invalidToken).map((r) => r.token);
    if (invalid.length) await db.from("push_tokens").delete().in("token", invalid);
    results.push({ user: c.user_id, kind: c.kind, ...text, author, sent: sendResults.some((r) => r.ok) });
  }

  return new Response(JSON.stringify({ candidates: candidates?.length ?? 0, chosen: chosen.length, dryRun, results: results.slice(0, 50) }), {
    headers: { "Content-Type": "application/json" },
  });
});
