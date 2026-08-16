import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";

// Live-Struktur einer Gasteig-HP8/Isarphilharmonie-Veranstaltungs-
// Detailseite (gasteig.de/veranstaltungen/<slug>/, verifiziert am
// 2026-08-14 gegen .../lucerne-festival-contemporary-orchestra-mit-joerg-widmann/):
//
//   <h2>Mitwirkende</h2><ul><li>Christoph Sietzen, Schlagzeug und Einstudierung</li>
//   <li>Lucerne Festival Contemporary Orchestra</li><li>Jörg Widmann, Leitung</li></ul>
//
// Reiner Text ohne Bio-Links — anders als bei Staatsoper/MPhil trägt diese
// Quelle deshalb KEINE website_url zu Personen bei, liefert aber die
// strukturierte Besetzung selbst (die die generische Scrape-Quelle bisher
// gar nicht erfasst). Das Eventfoto braucht hier KEINE Sonderbehandlung —
// og:image ist auf gasteig.de bereits sauber gesetzt (mit Fotograf im
// Dateinamen, z.B. "...©Florian-Ganslmeier-scaled.jpg") und wird schon über
// die bestehende coverImageDetection.ts-Kaskade gefunden.
export interface GasteigEventDetail {
  participants: EventParticipantCandidate[];
}

const MITWIRKENDE_PATTERN = /<h2>Mitwirkende<\/h2>\s*<ul>([\s\S]*?)<\/ul>/i;
const LI_PATTERN = /<li>([\s\S]*?)<\/li>/g;

// Technische/kreative Credits ohne musikalische Mitwirkung auf der Bühne —
// dieselbe Grundidee wie CREATIVE_ROLES in staatsoperDetail.ts, an das hier
// beobachtete Rollenvokabular angepasst.
const NON_PERFORMING_ROLES = /^(Licht|Klangregie|Regie|Bühne|Bühnenbild|Kostüme?|Kostümbild|Video|Dramaturgie|Produktionsleitung|Regieassistenz|Moderation)$/i;
// Platzhalter-Besetzung ("noch nicht bekannt") — auch als Präfix vor einem
// Gruppennamen wie "N.N. Schlagzeuggruppe" (unbenannte Schlagzeuggruppe),
// nicht nur als alleinstehender Name.
const PLACEHOLDER_NAME = /^(N\.N\.?|TBA|TBD)\b/i;

export function parseGasteigEventDetail(html: string): GasteigEventDetail {
  const participants: EventParticipantCandidate[] = [];
  const block = html.match(MITWIRKENDE_PATTERN)?.[1];
  if (!block) return { participants };

  for (const liMatch of block.matchAll(LI_PATTERN)) {
    const text = stripTags(liMatch[1]).replace(/\s+/g, " ").trim();
    if (!text || PLACEHOLDER_NAME.test(text)) continue;
    const commaIndex = text.indexOf(",");
    if (commaIndex < 0) {
      // Kein Komma → Ensemble-Name ohne eigene Rollenangabe (z.B. "Lucerne
      // Festival Contemporary Orchestra"), analog zur BRSO-Heuristik "keine
      // Rollenangabe = Ensemble" (siehe brsoDetail.ts).
      participants.push({ name: text, profileUrl: null, role: null, type: "ensemble" });
      continue;
    }
    const name = text.slice(0, commaIndex).trim();
    const roleRaw = text.slice(commaIndex + 1).trim();
    if (!name || NON_PERFORMING_ROLES.test(roleRaw)) continue;
    participants.push({ name, profileUrl: null, role: classifyRole(roleRaw), type: "person" });
  }

  return { participants };
}

function classifyRole(roleRaw: string): "dirigent" | "chorleiter" | "solist" {
  if (/leitung|dirigent|dirigat/i.test(roleRaw)) return "dirigent";
  if (/chorleit/i.test(roleRaw)) return "chorleiter";
  return "solist";
}

function stripTags(value: string): string {
  return value.replace(/<[^>]+>/g, " ");
}
