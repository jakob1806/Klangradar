// Erstellt von Claude Code (26.10.2026): Abonnement-/Zyklus-Erkennung aus den
// Detailseiten der Veranstalter. Die Quellen nennen das Abo direkt am Termin:
// mphil.de ("Abonnement B"/"Subscription B"), brso.de ("ABO D" je Datum),
// Musikverein (distributionChannels = Zyklus), wienersymphoniker.at
// ("Teil des Abonnements „…“" mit Link).
// deno-lint-ignore-file no-explicit-any

export interface SubscriptionCandidate {
  organizer: "mphil" | "brso" | "musikverein" | "wienersymphoniker";
  code: string;
  name: string;
  url: string | null;
}

const ORGANIZER_LABEL: Record<SubscriptionCandidate["organizer"], string> = {
  mphil: "Münchner Philharmoniker",
  brso: "BR Symphonieorchester",
  musikverein: "Musikverein Wien",
  wienersymphoniker: "Wiener Symphoniker",
};

const ORGANIZER_ABO_PAGE: Record<SubscriptionCandidate["organizer"], string> = {
  mphil: "https://www.mphil.de/abos",
  brso: "https://www.brso.de/abonnements/",
  musikverein: "https://musikverein.at/2026-27/abonnements",
  wienersymphoniker: "https://www.wienersymphoniker.at/abonnements",
};

function clean(text: string): string {
  let s = text;
  let prev: string;
  do {
    prev = s;
    s = s.replace(/<[^<>]*>/g, " ");
  } while (s !== prev);
  return s.replace(/[<>]/g, "").replace(/&bdquo;|&ldquo;|&rdquo;|&quot;/g, "").replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
}

/** Saison (Sept–Aug), z. B. "2026/27". */
export function seasonFor(start: string | Date): string {
  const d = new Date(start);
  const y = d.getUTCMonth() >= 8 ? d.getUTCFullYear() : d.getUTCFullYear() - 1;
  return `${y}/${String((y + 1) % 100).padStart(2, "0")}`;
}

export function mphilSubscriptions(html: string): SubscriptionCandidate[] {
  const out: SubscriptionCandidate[] = [];
  for (const m of html.matchAll(/concert-detail__topline">([\s\S]{0,200}?)<\/p>/g)) {
    const text = clean(m[1]);
    const abo = text.match(/^(?:Abonnement|Subscription|Abo)\s+(.+)$/i);
    if (!abo) continue;
    const code = abo[1].trim();
    out.push({ organizer: "mphil", code, name: `Abo ${code}`, url: ORGANIZER_ABO_PAGE.mphil });
  }
  return dedupe(out);
}

const MONTHS = ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"];

/** brso.de listet mehrere Termine pro Seite, jeder mit eigenem ABO-Badge. */
export function brsoSubscriptions(html: string, start: string | Date): SubscriptionCandidate[] {
  const text = clean(html);
  const d = new Date(start);
  const day = Number(new Intl.DateTimeFormat("de-DE", { day: "numeric", timeZone: "Europe/Berlin" }).format(d));
  const month = MONTHS[Number(new Intl.DateTimeFormat("de-DE", { month: "numeric", timeZone: "Europe/Berlin" }).format(d)) - 1];
  const year = d.getUTCFullYear();
  const dateRe = /(?:Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag)\s+(\d{1,2})\.?\s+([A-Za-zäÄ]+)\s+(\d{4})/g;
  const marks = [...text.matchAll(dateRe)];
  for (let i = 0; i < marks.length; i++) {
    const m = marks[i];
    if (Number(m[1]) !== day || m[2].toLowerCase() !== month || Number(m[3]) !== year) continue;
    const segment = text.slice(m.index!, marks[i + 1]?.index ?? m.index! + 600);
    const abos = [...segment.matchAll(/\bABO\s+([A-Z0-9][A-Za-z0-9+]{0,8})\b/g)].map((a) => a[1]);
    return dedupe(abos.map((code) => ({ organizer: "brso" as const, code, name: `Abo ${code}`, url: ORGANIZER_ABO_PAGE.brso })));
  }
  return [];
}

export function musikvereinSubscriptions(data: any): SubscriptionCandidate[] {
  const out: SubscriptionCandidate[] = [];
  for (const ch of data?.distributionChannels?.data ?? []) {
    const name = String(ch.description_D ?? "").trim();
    const code = String(ch.code ?? "").trim();
    // Zyklen tragen die Saison im Code (z. B. MEIIII2627); andere Kanäle nicht.
    if (!name || !/\d{4}$/.test(code)) continue;
    out.push({ organizer: "musikverein", code, name, url: ORGANIZER_ABO_PAGE.musikverein });
  }
  return dedupe(out);
}

export function wienerSymphonikerSubscriptions(html: string): SubscriptionCandidate[] {
  const out: SubscriptionCandidate[] = [];
  for (const m of html.matchAll(/Teil des Abonnements\s*(?:&bdquo;|„)([^<&“]+)(?:&ldquo;|&rdquo;|“)[\s\S]{0,400}?href="(\/abonnement\/[^"]+)"/g)) {
    const name = m[1].trim();
    out.push({ organizer: "wienersymphoniker", code: m[2].split("/").pop()!, name, url: `https://www.wienersymphoniker.at${m[2]}` });
  }
  return dedupe(out);
}

function dedupe(items: SubscriptionCandidate[]): SubscriptionCandidate[] {
  const seen = new Set<string>();
  return items.filter((s) => !seen.has(s.organizer + s.code) && seen.add(s.organizer + s.code));
}

/** Abos anlegen/finden und dem Termin zuordnen (ersetzt bestehende Zuordnung derselben Veranstalter). */
export async function linkEventSubscriptions(supabase: any, eventId: string, start: string, subs: SubscriptionCandidate[]): Promise<number> {
  if (subs.length === 0) return 0;
  const season = seasonFor(start);
  const ids: string[] = [];
  for (const s of subs) {
    const { data, error } = await supabase.from("concert_subscriptions").upsert({
      organizer: s.organizer, organizer_name: ORGANIZER_LABEL[s.organizer], code: s.code, name: s.name, season, url: s.url,
    }, { onConflict: "organizer,season,code" }).select("id").single();
    if (!error && data?.id) ids.push(data.id);
  }
  await supabase.from("event_concert_subscriptions").delete().eq("event_id", eventId);
  if (ids.length) await supabase.from("event_concert_subscriptions").insert(ids.map((id) => ({ event_id: eventId, subscription_id: id })));
  return ids.length;
}
