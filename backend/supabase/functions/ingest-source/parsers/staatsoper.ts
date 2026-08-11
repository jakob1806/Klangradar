// Bayerische Staatsoper: der offizielle Spielplan blockiert direkte
// Server-Fetches mit einer 403-Challenge. Der Jina-Reader liefert denselben
// öffentlich sichtbaren Inhalt als Markdown und behält die offiziellen
// staatsoper.de-Detail-URLs bei. So können wir Termine vollständig und mit
// stabiler externer ID einlesen; Programm/Besetzung kommen anschließend aus
// der Detailseite über fetchPageText()s gleichartigen Fallback.

import type { ParseResult, RawEvent } from "../types.ts";
import { USER_AGENT } from "../../_shared/robots.ts";

const MONTHS_AHEAD_DEFAULT = 12;

export async function fetchStaatsoperSchedule(
  baseUrl: string,
  monthsAhead = MONTHS_AHEAD_DEFAULT,
): Promise<string> {
  const now = new Date();
  const pages: string[] = [];
  for (let offset = 0; offset < Math.min(Math.max(monthsAhead, 1), 18); offset++) {
    // Reader-Dienst vor Burst-Last schützen; ohne Abstand trat im echten
    // 12-Monats-Lauf nach einigen Seiten HTTP 429 auf.
    if (offset > 0) await new Promise((resolve) => setTimeout(resolve, 1100));
    const month = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + offset, 1));
    const ym = `${month.getUTCFullYear()}-${String(month.getUTCMonth() + 1).padStart(2, "0")}`;
    const officialUrl = `${baseUrl.replace(/\/$/, "")}/${ym}`;
    const readerUrl = `https://r.jina.ai/${officialUrl}`;
    let res = await fetch(readerUrl, { headers: { "User-Agent": USER_AGENT } });
    for (let attempt = 1; !res.ok && attempt < 3; attempt++) {
      const retrySeconds = res.status === 429
        ? Math.min(Number(res.headers.get("retry-after") ?? 3) || 3, 10)
        : attempt * 2;
      await new Promise((resolve) => setTimeout(resolve, retrySeconds * 1000));
      res = await fetch(readerUrl, { headers: { "User-Agent": USER_AGENT } });
    }
    if (!res.ok) {
      // Niemals eine Teilsaison als vollständigen Spielplan weiterreichen:
      // Der Paket-Cursor wäre sonst auf einer wechselnden Liste ungültig.
      throw new Error(`Staatsoper reader fetch ${ym}: HTTP ${res.status}`);
    }
    pages.push(await res.text());
  }
  return pages.join("\n\n");
}

export function parseStaatsoper(markdown: string): ParseResult {
  const events: RawEvent[] = [];
  const errors: string[] = [];
  const seen = new Set<string>();
  const linkPattern = /\[([^\]]*?Weitere Informationen zu ([\s\S]*?) anzeigen - (\d{2})\.(\d{2})\.(\d{4}), (\d{2})[.:](\d{2}) Uhr[^\]]*)\]\((https:\/\/www\.staatsoper\.de\/(?:stuecke|produktionen)\/[^)]+)\)/g;

  for (const match of markdown.matchAll(linkPattern)) {
    const [, label, rawTitle, day, month, year, hour, minute, url] = match;
    if (seen.has(url)) continue;
    seen.add(url);
    const title = clean(rawTitle);
    // Klangradar zeigt Aufführungen, nicht den kompletten Betriebs-/
    // Vermittlungskalender des Hauses. Die offizielle Linkzeile endet mit
    // der Kategorie; nur musikalische Bühnen- und Konzertformate zulassen.
    const categoryTail = clean(label.slice(label.lastIndexOf("Uhr") + 3));
    if (!/\b(Oper|Ballett|Konzert|Liederabend)\b/i.test(categoryTail)) continue;
    // Manche Vermittlungsformate werden auf der Website trotzdem pauschal
    // als „Ballett“ kategorisiert. Sie sind keine Aufführungen und werden
    // deshalb zusätzlich über ihren eindeutigen Titel ausgeschlossen.
    if (/(?:^|[\s-])(?:Kurzführungen?|Führungen?|Bühnenproben?|Proben?|Workshops?)(?:$|[\s:–—-])/i.test(title)) continue;
    const startDateTime = toBerlinIso(+year, +month, +day, +hour, +minute);
    if (!startDateTime) {
      errors.push(`Staatsoper: ungültiges Datum für "${title}"`);
      continue;
    }

    const beforeInfo = clean(label.split("Weitere Informationen zu")[0]);
    const afterClock = beforeInfo.replace(/^.*?Uhr\s*\|\s*/, "");
    const titleIndex = afterClock.toLocaleLowerCase("de").lastIndexOf(title.toLocaleLowerCase("de"));
    const venueAndFlags = titleIndex >= 0 ? afterClock.slice(0, titleIndex).trim() : "";
    let venueName = clean(venueAndFlags.split("|")[0]) || null;
    if (/Gastspiel|Baden-Baden|Meiningen|Aschaffenburg|Salzburg|Wien|Paris/i.test(`${title} ${venueName ?? ""}`)) continue;
    // Spielräume innerhalb desselben Hauses auf die vorhandene kanonische
    // Venue abbilden, statt Aufführungen wegen eines Foyer-/Saalzusatzes zu
    // verlieren. Die Detailansicht behält den Originaltext weiterhin über
    // die offizielle URL/Anreicherung.
    if (venueName && /Nationaltheater|Freunde-Foyer|Königssaal|Parkettgarderobe/i.test(venueName)) {
      venueName = "Nationaltheater München";
    } else if (venueName && /Gartensaal Prinzregententheater/i.test(venueName)) {
      venueName = "Prinzregententheater";
    }
    const afterTitle = titleIndex >= 0 ? clean(afterClock.slice(titleIndex + title.length)) : "";

    events.push({
      externalId: url,
      title,
      description: afterTitle || null,
      startDateTime,
      endDateTime: null,
      venueName,
      venueAddress: null,
      url,
      imageUrl: null,
      priceMin: null,
      priceMax: null,
      isFree: /eintritt frei/i.test(label) || null,
    });
  }

  if (events.length === 0) errors.push("Staatsoper: keine Termine im Reader-Inhalt erkannt");
  return { events, errors };
}

function clean(value: string): string {
  return value.replace(/[_*]/g, "").replace(/\s+/g, " ").trim();
}

function toBerlinIso(year: number, month: number, day: number, hour: number, minute: number): string | null {
  const probe = new Date(Date.UTC(year, month - 1, day));
  if (probe.getUTCFullYear() !== year || probe.getUTCMonth() !== month - 1 || probe.getUTCDate() !== day) return null;
  const lastSunday = (monthIndex: number) => {
    const last = new Date(Date.UTC(year, monthIndex + 1, 0));
    return last.getUTCDate() - last.getUTCDay();
  };
  const summer = month > 3 && month < 10 ||
    (month === 3 && (day > lastSunday(2) || day === lastSunday(2) && hour >= 2)) ||
    (month === 10 && (day < lastSunday(9) || day === lastSunday(9) && hour < 3));
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:00${summer ? "+02:00" : "+01:00"}`;
}
