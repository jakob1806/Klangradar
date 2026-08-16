import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";
import { isLikelyGenericImage } from "./imageValidation.ts";

// Live-Struktur einer BRSO-Konzert-Detailseite (brso.de/konzerte/<slug>/,
// verifiziert am 2026-08-14 gegen https://www.brso.de/konzerte/sir-simon-
// rattle-beethoven-9/): normales serverseitig gerendertes HTML (kein
// r.jina.ai-Reader nötig, anders als bei staatsoper.de), og:image bereits
// sauber gesetzt, Besetzung als Klartext-Liste ohne eigene Bio-Links:
//
//   <h3 class="h3">Mitwirkende</h3>
//   ...
//   <div class="mb-1.5 last:mb-0">
//     <span class="font-bold">Sir Simon Rattle</span>
//     <span>Dirigent</span>
//   </div>
//   <div class="mb-1.5 last:mb-0">
//     <span class="font-bold">Chor des Bayerischen Rundfunks</span>
//   </div>
//
// Personen haben immer zwei <span>s (Name, Rolle), Ensembles nur eines
// (Name) — diese Unterscheidung reicht hier aus, ohne zusätzlich auf
// Schlagwörter wie "orchester"/"chor" im Namen angewiesen zu sein (die
// generische Ablehnung zu allgemeiner Namen bleibt trotzdem über
// resolveEnsembles()/GENERIC_ENSEMBLE_NAMES aktiv, siehe
// eventParticipantResolution.ts).

export interface BrsoEventDetail {
  imageUrl: string | null;
  credits: string | null;
  participants: EventParticipantCandidate[];
}

const OG_IMAGE_PATTERN = /<meta\s+property=["']og:image["']\s+content=["']([^"']+)["']/i;
const MITWIRKENDE_HEADING_PATTERN = /<h3[^>]*>\s*Mitwirkende\s*<\/h3>/i;
const ROW_PATTERN = /<div class="mb-1\.5 last:mb-0">([\s\S]*?)<\/div>/g;
const SPAN_TEXT_PATTERN = /<span[^>]*>([\s\S]*?)<\/span>/g;
const CREDIT_PATTERN = /©[^<\n]{2,80}/;

export function parseBrsoEventDetail(html: string): BrsoEventDetail {
  // Live-Fund (br-chor.de, dieselbe Seitenvorlage wie brso.de): manche
  // Seiten dieser Vorlage setzen kein eigenes og:image pro Termin, sondern
  // überall dasselbe Site-Logo — ungefiltert würde das als Eventfoto
  // übernommen. brso.de selbst hat pro Konzert ein eigenes og:image, ist
  // von diesem Filter also nicht betroffen.
  const rawImageUrl = html.match(OG_IMAGE_PATTERN)?.[1] ?? null;
  const imageUrl = rawImageUrl && !isLikelyGenericImage(rawImageUrl) ? rawImageUrl : null;
  const credits = html.match(CREDIT_PATTERN)?.[0]?.trim() ?? null;

  const headingMatch = html.match(MITWIRKENDE_HEADING_PATTERN);
  const participants: EventParticipantCandidate[] = [];
  if (headingMatch?.index !== undefined) {
    // Die Besetzungsliste endet spätestens am nächsten "<section" — danach
    // folgen unabhängige Inhaltsblöcke (Sponsoren-Logos, Programmtext), die
    // hier nicht mehr geparst werden sollen.
    const sectionEnd = html.indexOf("<section", headingMatch.index + headingMatch[0].length);
    const block = html.slice(
      headingMatch.index + headingMatch[0].length,
      sectionEnd >= 0 ? sectionEnd : undefined,
    );
    for (const rowMatch of block.matchAll(ROW_PATTERN)) {
      const spans = [...rowMatch[1].matchAll(SPAN_TEXT_PATTERN)]
        .map((m) => m[1].replace(/\s+/g, " ").trim())
        .filter(Boolean);
      if (spans.length === 0) continue;
      const [name, roleRaw] = spans;
      if (roleRaw) {
        participants.push({ name, profileUrl: null, role: classifyRole(roleRaw), type: "person" });
      } else {
        participants.push({ name, profileUrl: null, role: null, type: "ensemble" });
      }
    }
  }

  return { imageUrl, credits, participants };
}

function classifyRole(roleRaw: string): "dirigent" | "chorleiter" | "solist" {
  // "Leitung" live auf br-chor.de gefunden (dieselbe Vorlage wie brso.de,
  // dort steht literal "Dirigent") — beide Formulierungen meinen dieselbe
  // Rolle.
  if (/dirigent|^leitung$/i.test(roleRaw)) return "dirigent";
  if (/chorleit/i.test(roleRaw)) return "chorleiter";
  return "solist";
}
