// Ticket Intelligence (Nutzeranfrage): "Defekte oder nicht mehr gültige
// Ticketlinks automatisch erkennen". Prüft periodisch event_ticket_links
// künftiger Events per HEAD-Request (Fallback GET, falls der Server HEAD
// nicht unterstützt — manche Ticketsysteme antworten darauf mit 405).
// Ein Link gilt als defekt nur bei einem eindeutigen "Seite existiert
// nicht mehr" (404/410/400) oder wenn die Verbindung komplett fehlschlägt
// (DNS-Fehler, Timeout, Verbindung abgelehnt) — nicht bei Redirects (bei
// Ticketanbietern normal, z.B. Session-Handling).
//
// 401/403/429/503 werden bewusst NICHT als defekt gewertet: viele
// Ticketanbieter (u.a. staatsoper.de, hinter Cloudflare) blocken jeden
// Server-zu-Server-Request mit 403 Bot-Schutz, obwohl der Link im Browser
// einwandfrei funktioniert (verifiziert per curl mit Browser-User-Agent —
// identisches 403 trotzdem). Ein Feature, das bei jedem Cloudflare-
// geschützten Anbieter fälschlich "defekt" schreit, wäre schlimmer als gar
// keine Prüfung — Redaktion würde dem Alarm irgendwann nicht mehr trauen.
//
// Bewusst kein Versuch, den Seiteninhalt zu interpretieren ("ausverkauft"-
// Text erkennen o.ä.) — das wäre pro Anbieter unterschiedlich und fragil.
//
// Aufruf: POST {} — läuft täglich per Cron, maximal 100 Links pro Lauf
// (älteste zuerst / noch nie geprüfte zuerst), damit ein einzelner Lauf
// nicht Minuten dauert und keine Anbieter-Server mit Traffic überzieht.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface LinkRow {
  event_id: string;
  url: string;
}

// Eindeutig "existiert nicht mehr". Alles andere (inkl. 401/403/429/5xx
// außer 501) gilt als "kann gerade nicht zuverlässig geprüft werden", nicht
// als defekt — siehe Kommentar oben.
const DEFINITELY_GONE = new Set([400, 404, 410]);

async function checkStatus(url: string): Promise<number | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  const headers = { "User-Agent": "Mozilla/5.0 (compatible; KlangradarLinkCheck/1.0)" };
  try {
    const head = await fetch(url, { method: "HEAD", redirect: "follow", signal: controller.signal, headers });
    if (head.status === 405 || head.status === 501) {
      // Server lehnt HEAD kategorisch ab -> mit GET nachprüfen.
      const get = await fetch(url, { method: "GET", redirect: "follow", signal: controller.signal, headers });
      return get.status;
    }
    return head.status;
  } catch {
    // Verbindung komplett fehlgeschlagen (DNS, Timeout, Refused) — das
    // IST ein eindeutiges Signal, anders als ein blockierter Statuscode.
    return -1;
  } finally {
    clearTimeout(timeout);
  }
}

async function isBroken(url: string): Promise<boolean> {
  const status = await checkStatus(url);
  if (status === -1) return true;
  if (status === null) return false;
  return DEFINITELY_GONE.has(status);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Nur POST" }), { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: links, error } = await supabase
    .from("event_ticket_links")
    .select("event_id, url, events!inner(status, start_datetime)")
    .eq("events.status", "scheduled")
    .gte("events.start_datetime", new Date().toISOString())
    .order("last_checked_at", { ascending: true, nullsFirst: true })
    .limit(100)
    .returns<(LinkRow & { events: { status: string; start_datetime: string } })[]>();

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
  if (!links || links.length === 0) {
    return new Response(JSON.stringify({ checked: 0, message: "Keine anstehenden Events mit Ticket-Link." }));
  }

  let checked = 0;
  let broken = 0;
  const errors: string[] = [];

  for (const link of links) {
    try {
      const brokenResult = await isBroken(link.url);
      await supabase
        .from("event_ticket_links")
        .update({ last_checked_at: new Date().toISOString(), is_broken: brokenResult })
        .eq("event_id", link.event_id)
        .eq("url", link.url);
      checked++;
      if (brokenResult) broken++;
    } catch (err) {
      errors.push(`${link.event_id}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(JSON.stringify({ checked, broken, errors: errors.length > 0 ? errors : undefined }));
});
