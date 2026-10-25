// Erstellt von Claude Code (Nutzerwunsch 25.10.2026): Programmhefte für
// ALLE Konzerte suchen, auch bestehende, und erneut prüfen, bis eins da ist
// (Hefte erscheinen meist erst ~1 Woche vor dem Termin).
//
//   Münchner Philharmoniker: PDFs liegen nach festem Muster unter
//     /fileadmin/Redaktion-mphil/Saisonordner/Saison_<JJjj>/Programmhefte/
//     <JJJJMMTT>_Programmheft_<Nachname>_www.pdf
//     (Datum = erster Termin der Reihe, Nachname = meist Dirigent:in).
//     Wir probieren alle Termine der Reihe × alle Mitwirkenden (HEAD).
//   Alle anderen: Konzertseite laden und Programmheft-Links suchen
//     (_shared/programBooklet.ts).
//
// Aufruf (intern/Cron): POST { limit? }
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { findProgramBooklet } from "../_shared/programBooklet.ts";
import { requireInternalAuth } from "../_shared/internalAuth.ts";
import { USER_AGENT } from "../_shared/robots.ts";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function seasonFolder(date: Date): string {
  // Saison läuft Sep–Jul: 2026-10 → Saison_2627
  const y = date.getUTCFullYear();
  const start = date.getUTCMonth() >= 7 ? y : y - 1;
  return `Saison_${String(start).slice(2)}${String(start + 1).slice(2)}`;
}

function ymd(date: Date): string {
  return date.toLocaleDateString("sv-SE", { timeZone: "Europe/Berlin" }).replaceAll("-", "");
}

function surnameVariants(name: string): string[] {
  const last = name.trim().split(/\s+/).pop() ?? "";
  const ascii = last.normalize("NFD").replace(/[̀-ͯ]/g, "");
  return [...new Set([last, ascii].filter((v) => v.length > 1))];
}

async function exists(url: string): Promise<boolean> {
  try {
    const res = await fetch(url, { method: "HEAD", headers: { "User-Agent": USER_AGENT } });
    return res.ok && (res.headers.get("content-type") ?? "").includes("pdf");
  } catch {
    return false;
  }
}

// deno-lint-ignore no-explicit-any
async function mphilBooklet(supabase: any, event: any): Promise<string | null> {
  // Termine derselben Reihe (gleiche Seite → gleiche Programm-URL-Basis).
  const base = String(event.external_id ?? event.website_url).replace(/-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}$/, "");
  const { data: siblings } = await supabase.from("events").select("start_datetime")
    .ilike("external_id", `${base}%`).order("start_datetime");
  const dates = [...new Set([...(siblings ?? []).map((s: any) => ymd(new Date(s.start_datetime))), ymd(new Date(event.start_datetime))])].sort();
  const names = (event.event_participants ?? [])
    .map((p: any) => p.persons?.full_name).filter(Boolean)
    .flatMap(surnameVariants);
  const folder = seasonFolder(new Date(event.start_datetime));
  for (const date of dates) {
    for (const name of names) {
      const url = `https://www.mphil.de/fileadmin/Redaktion-mphil/Saisonordner/${folder}/Programmhefte/${date}_Programmheft_${encodeURIComponent(name)}_www.pdf`;
      if (await exists(url)) return url;
    }
  }
  return null;
}

// deno-lint-ignore no-explicit-any
async function pageBooklet(event: any): Promise<string | null> {
  const url = event.website_url ?? event.external_id;
  if (!url || !/^https?:/.test(url)) return null;
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) return null;
    return findProgramBooklet(await res.text(), url);
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  const unauthorized = await requireInternalAuth(req);
  if (unauthorized) return unauthorized;
  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Math.max(Number(body.limit) || 30, 1), 60);
  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  // Kommende 6 Wochen + letzte 2 Wochen, noch ohne Heft, zuletzt geprüft
  // vor > 20 h (oder nie) – die nächsten Termine zuerst.
  const now = Date.now();
  const { data: events } = await supabase.from("events")
    .select("id,start_datetime,website_url,external_id,event_participants(persons(full_name))")
    .is("program_booklet_url", null)
    .in("status", ["scheduled", "sold_out"])
    .gte("start_datetime", new Date(now - 14 * 86_400_000).toISOString())
    .lte("start_datetime", new Date(now + 42 * 86_400_000).toISOString())
    .or(`program_booklet_checked_at.is.null,program_booklet_checked_at.lt.${new Date(now - 20 * 3_600_000).toISOString()}`)
    .order("start_datetime")
    .limit(limit);

  let found = 0;
  for (const event of events ?? []) {
    const isMphil = /mphil\.de\//.test(`${event.external_id} ${event.website_url}`);
    const booklet = isMphil ? (await mphilBooklet(supabase, event)) ?? (await pageBooklet(event)) : await pageBooklet(event);
    await supabase.from("events").update({ program_booklet_url: booklet, program_booklet_checked_at: new Date().toISOString() }).eq("id", event.id);
    if (booklet) found++;
  }
  return json({ processed: events?.length ?? 0, found });
});
