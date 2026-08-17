import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";

// Live-Struktur einer Staatstheater-am-Gärtnerplatz-Produktionsseite
// (gaertnerplatztheater.de/de/produktionen/<slug>.html?ID_Vorstellung=...,
// verifiziert am 2026-08-15/16 gegen .../produktionen/la-traviata.html):
//
//   <div id="besetzungBox">...
//     <div class="function_person">
//       <span class="function ...">Dirigat</span>
//       <span class="person ..."><a ... href="personen/ruben-dubrovsky.html">Rubén Dubrovsky</a></span>
//     </div>
//     ...(Regie/Bühne/Kostüme/Choreografie/Licht/Dramaturgie — Kreativteam)...
//     <div class="function_person">
//       <span class="function ...">Violetta Valéry</span>
//       <span class="person ..."><a ... href="personen/jennifer-oloughlin.html">Jennifer O'Loughlin</a></span>
//     </div>
//     ...(weitere Partien, teils ohne Bio-Link, nur Klartext-Name)...
//     <p><b>Chor, Statisterie und Kinderstatisterie des Staatstheaters am Gärtnerplatz</b>
//        <br><b>Orchester des Staatstheaters am Gärtnerplatz</b></p>
//   </div>
//   <div id="termineBox">...
//
// Reichste Quelle nach Staatsoper: Bio-Links für (fast) alle Mitwirkenden
// UND eigenes og:image auf der Bio-Seite (kein Eventfoto auf der
// Produktionsseite selbst nötig — dieselbe Grundidee wie bei MPhil/MKO,
// nur mit Bio-Link-Rückverlinkung wie bei Staatsoper).
export interface GaertnerplatzEventDetail {
  participants: EventParticipantCandidate[];
}

const BESETZUNG_START = /<div id="besetzungBox"/i;
const BESETZUNG_END = /<div id="termineBox"/i;
const FUNCTION_PERSON_PATTERN = /<div class="function_person">([\s\S]*?)<\/div>/g;
const FUNCTION_PATTERN = /<span class="function[^"]*">([\s\S]*?)<\/span>/;
const PERSON_SPAN_PATTERN = /<span class="person[^"]*">([\s\S]*?)<\/span>/;
const PERSON_LINK_PATTERN = /<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/;
const ENSEMBLE_PATTERN = /<b>([^<]+)<\/b>/g;

// Kreativ-/technisches Team ohne musikalische Mitwirkung auf der Bühne —
// dieselbe Grundidee wie CREATIVE_ROLES in staatsoperDetail.ts.
const NON_PERFORMING_ROLES = /^(Inszenierung|Regie|Bühne|Bühnenbild|Kostüme?|Kostümbild|Licht|Video|Dramaturgie|Choreographie|Choreografie|Produktionsleitung|Regieassistenz)$/i;

// Live-Fund: relative Links auf dieser Seite (Produktions- wie Bio-Links)
// lösen NICHT gegen die aktuelle Seiten-URL auf, sondern immer gegen
// "/de/" — dieselbe baseUrl, die auch der bestehende Spielplan-Scraper
// dafür konfiguriert hat (siehe 20260804000001-Migration o.ä.,
// config.baseUrl = "https://www.gaertnerplatztheater.de/de/"). Ein
// naiver new URL(href, pageUrl) gegen die Produktionsseite selbst
// erzeugte 404-Bio-Links (.../produktionen/personen/... statt
// .../personen/...).
const BASE_URL = "https://www.gaertnerplatztheater.de/de/";

export function parseGaertnerplatzEventDetail(html: string): GaertnerplatzEventDetail {
  const startMatch = html.match(BESETZUNG_START);
  if (!startMatch || startMatch.index === undefined) return { participants: [] };
  const endMatch = BESETZUNG_END.exec(html.slice(startMatch.index!));
  const block = endMatch
    ? html.slice(startMatch.index!, startMatch.index! + endMatch.index)
    : html.slice(startMatch.index!);

  const participants: EventParticipantCandidate[] = [];
  let lastPersonEnd = 0;
  for (const match of block.matchAll(FUNCTION_PERSON_PATTERN)) {
    lastPersonEnd = (match.index ?? 0) + match[0].length;
    const entry = match[1];
    const roleRaw = entry.match(FUNCTION_PATTERN)?.[1]?.replace(/\s+/g, " ").trim();
    const personBlock = entry.match(PERSON_SPAN_PATTERN)?.[1] ?? "";
    if (!roleRaw || NON_PERFORMING_ROLES.test(roleRaw)) continue;

    const link = personBlock.match(PERSON_LINK_PATTERN);
    const name = (link ? link[2] : stripTags(personBlock)).replace(/\s+/g, " ").trim();
    if (!name) continue;
    let profileUrl: string | null = null;
    if (link) {
      try {
        profileUrl = new URL(link[1], BASE_URL).toString();
      } catch {
        profileUrl = null;
      }
    }
    participants.push({ name, profileUrl, role: classifyRole(roleRaw), type: "person" });
  }

  // Ensembles (Chor/Orchester des Hauses) stehen als <b>-Zeilen NACH dem
  // letzten Mitwirkenden-Eintrag, siehe Datei-Kommentar.
  const tail = block.slice(lastPersonEnd);
  for (const match of tail.matchAll(ENSEMBLE_PATTERN)) {
    const name = match[1].replace(/\s+/g, " ").trim();
    if (name) participants.push({ name, profileUrl: null, role: null, type: "ensemble" });
  }

  return { participants };
}

function classifyRole(roleRaw: string): "dirigent" | "chorleiter" | "solist" {
  if (/dirigat|dirigent/i.test(roleRaw)) return "dirigent";
  if (/chorleit|choreinstudierung/i.test(roleRaw)) return "chorleiter";
  return "solist";
}

function stripTags(value: string): string {
  return value.replace(/<[^>]+>/g, " ");
}
