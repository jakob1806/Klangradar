// Erstellt von Claude Code (26.10.2026): Abonnement-/Zyklus-Erkennung aus den
// Detailseiten der Veranstalter. Die Quellen nennen das Abo direkt am Termin:
// mphil.de ("Abonnement B"/"Subscription B"), brso.de ("ABO D" je Datum),
// Musikverein (distributionChannels = Zyklus), wienersymphoniker.at
// ("Teil des Abonnements „…“" mit Link).
// Ergänzt 27.10.2026: weitere Münchner Quellen – Münchner Rundfunkorchester
// (Reihe wie "Sonntagskonzerte" je Termin), BR-Chor ("Teil des
// Chor-Abonnements"), Münchener Kammerorchester ("Abo 3" in Titel/URL) und
// Gärtnerplatztheater (Abo-Seite listet alle Serien mit exakten Terminen).
// Nicht möglich: Bayerische Staatsoper (blockt Abrufe mit 403), Münchner
// Symphoniker (Reihe steht nicht auf der Konzertseite).
// deno-lint-ignore-file no-explicit-any

export interface SubscriptionCandidate {
  organizer: "mphil" | "brso" | "musikverein" | "wienersymphoniker" | "rundfunkorchester" | "brchor" | "mko" | "gaertnerplatz";
  code: string;
  name: string;
  url: string | null;
}

const ORGANIZER_LABEL: Record<SubscriptionCandidate["organizer"], string> = {
  mphil: "Münchner Philharmoniker",
  brso: "BR Symphonieorchester",
  musikverein: "Musikverein Wien",
  wienersymphoniker: "Wiener Symphoniker",
  rundfunkorchester: "Münchner Rundfunkorchester",
  brchor: "BR-Chor",
  mko: "Münchener Kammerorchester",
  gaertnerplatz: "Gärtnerplatztheater",
};

const ORGANIZER_ABO_PAGE: Record<SubscriptionCandidate["organizer"], string> = {
  mphil: "https://www.mphil.de/abos",
  brso: "https://www.brso.de/abonnements/",
  musikverein: "https://musikverein.at/2026-27/abonnements",
  wienersymphoniker: "https://www.wienersymphoniker.at/abonnements",
  rundfunkorchester: "https://www.rundfunkorchester.de/konzerte-tickets/abonnements/",
  brchor: "https://www.br-chor.de/konzerte-tickets/abonnements/",
  mko: "https://www.m-k-o.eu/tickets/abonnements/",
  gaertnerplatz: "https://www.gaertnerplatztheater.de/de/seiten/abo.html",
};

function clean(text: string): string {
  // Skripte/Styles/Kommentare zuerst entfernen: Vergleiche wie "a < b" in
  // Inline-Skripten ließen die Tag-Schleife sonst ganze Seitenbereiche
  // verschlucken (brso.de: von ~15.000 Zeichen Text blieben 675 übrig).
  let s = text
    .replace(/<script\b[\s\S]*?<\/script\b[^>]*>/gi, " ")
    .replace(/<style\b[\s\S]*?<\/style\b[^>]*>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ");
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
  // Das Datum kann mehrfach vorkommen (Kopfbereich, Terminliste, "Weitere
  // Konzerte"); alle passenden Abschnitte auswerten statt beim ersten
  // Treffer ohne Abo-Badge aufzuhören (letzter Termin einer Seite fiel so aus).
  const abos: string[] = [];
  for (let i = 0; i < marks.length; i++) {
    const m = marks[i];
    if (Number(m[1]) !== day || m[2].toLowerCase() !== month || Number(m[3]) !== year) continue;
    const segment = text.slice(m.index!, marks[i + 1]?.index ?? m.index! + 600);
    // Nur bis zum Programm-/Mitwirkenden-Block: danach folgen andere Konzerte.
    const own = segment.split(/\b(?:Programm|Mitwirkende|Weitere Konzerte)\b/)[0];
    abos.push(...[...own.matchAll(/\bABO\s+([A-Z0-9][A-Za-z0-9+]{0,8})\b/g)].map((a) => a[1]));
  }
  return dedupe(abos.map((code) => ({ organizer: "brso" as const, code, name: `Abo ${code}`, url: ORGANIZER_ABO_PAGE.brso })));
}

/** rundfunkorchester.de: Reihe direkt nach dem Preisblock ("… 10,– (U30) Sonntagskonzerte"). */
export function rundfunkorchesterSubscriptions(html: string): SubscriptionCandidate[] {
  const text = clean(html);
  const names = [...text.matchAll(/\(U30\)\s+([A-ZÄÖÜ][a-zäöüß]+konzerte|Paradisi gloria|Klassik zum Staunen|Abenteuer Klassik)\b/g)].map((m) => m[1]);
  return dedupe(names.map((name) => ({ organizer: "rundfunkorchester" as const, code: name, name, url: ORGANIZER_ABO_PAGE.rundfunkorchester })));
}

/** br-chor.de: "Dieses Konzert ist Teil des Chor-Abonnements." */
export function brChorSubscriptions(html: string): SubscriptionCandidate[] {
  return /Teil des Chor-Abonnements/.test(clean(html))
    ? [{ organizer: "brchor", code: "Chor-Abo", name: "Chor-Abonnement", url: ORGANIZER_ABO_PAGE.brchor }]
    : [];
}

/** m-k-o.eu: Abonnementkonzerte tragen "Abo 3" o. Ä. in Titel bzw. URL. */
export function mkoSubscriptions(url: string, title = ""): SubscriptionCandidate[] {
  const haystack = `${decodeURIComponent(url).replace(/\+/g, " ")} ${title}`;
  return /\bAbo\s*\d+\b/i.test(haystack)
    ? [{ organizer: "mko", code: "Abo", name: "Abonnementkonzerte", url: ORGANIZER_ABO_PAGE.mko }]
    : [];
}

export interface GaertnerplatzSeries {
  code: string;
  name: string;
  /** Ortszeit Europe/Berlin, "YYYY-MM-DD HH:MM" */
  dates: string[];
}

/** gaertnerplatztheater.de/de/seiten/abos-JJJJ-JJJJ.html: je "Abo Serie NN"
 * ein Block mit allen Terminen ("Fr, 16.10.26 19.30–22.20 Uhr …"). Der Name
 * steht davor ("Premieren-Abo", "Kammerkonzerte", "U30-Abo" …). */
export function gaertnerplatzSeries(html: string): GaertnerplatzSeries[] {
  const text = clean(html);
  const marks = [...text.matchAll(/Abo Serie (\d{2})\b/g)];
  return marks.map((m, i) => {
    const before = text.slice(Math.max(0, m.index! - 120), m.index!);
    const label = before.split(/(?:buchen|ansehen|Online-Buchung|€)\s*/).pop()?.trim() ?? "";
    const block = text.slice(m.index!, marks[i + 1]?.index ?? m.index! + 4000);
    const dates = [...block.matchAll(/(?:Mo|Di|Mi|Do|Fr|Sa|So), (\d{2})\.(\d{2})\.(\d{2}) (\d{1,2})\.(\d{2})/g)]
      .map((d) => `20${d[3]}-${d[2]}-${d[1]} ${d[4].padStart(2, "0")}:${d[5]}`);
    const name = label && label.length <= 40 ? `${label} (Serie ${m[1]})` : `Abo-Serie ${m[1]}`;
    return { code: `Serie ${m[1]}`, name, dates };
  }).filter((s) => s.dates.length > 0);
}

export function gaertnerplatzSubscriptions(series: GaertnerplatzSeries[], start: string | Date, pageUrl?: string): SubscriptionCandidate[] {
  const local = berlinLocal(start);
  return dedupe(series.filter((s) => s.dates.includes(local))
    .map((s) => ({ organizer: "gaertnerplatz" as const, code: s.code, name: s.name, url: pageUrl ?? ORGANIZER_ABO_PAGE.gaertnerplatz })));
}

/** "YYYY-MM-DD HH:MM" in Europe/Berlin */
export function berlinLocal(start: string | Date): string {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("de-DE", {
    timeZone: "Europe/Berlin", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(new Date(start)).map((p) => [p.type, p.value]));
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`;
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
