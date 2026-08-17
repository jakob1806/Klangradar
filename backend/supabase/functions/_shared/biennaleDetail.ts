import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";

// Live-Struktur einer Münchener-Biennale-Produktionsseite
// (muenchener-biennale.de/en/programm/kalender/<slug>, verifiziert am
// 2026-08-16 gegen .../kalender/crypt):
//
//   <div class="info"><span class="label t5"><p>Musical direction:</p></span>
//     <span>&nbsp;</span><span class="artist bold t5">CHRISTIAN EGGEN</span></div>
//   <div class="info"><span class="label t5"><p>Violin:</p></span>
//     <span>&nbsp;</span><span class="artist bold t5">KARIN HELLQVIST</span>
//     <span class="bold sep t5">,</span><span>&nbsp;</span>
//     <span class="artist bold t5">EMILIE LIDSHEIM</span></div>
//   <div class="info"><span class="label t5"></span>
//     <span class="artist bold t5">OSLO SINFONIETTA</span></div>
//
// Ein "info"-Eintrag kann mehrere Namen zu EINER Rolle enthalten (z.B.
// mehrere Geiger:innen). Ensembles haben ein LEERES label-<span> (kein
// <p> darin) — dieselbe Grundidee wie die BRSO-Heuristik "keine
// Rollenangabe = Ensemble", nur am leeren statt fehlenden Element erkannt.
// Internationales Gastfestival: kein festes Hausorchester, deshalb keine
// automatische Ensemble-Ergänzung wie bei MPhil/MKO. Kein eigenes
// og:image auf der Produktionsseite — die Bildrecherche läuft über die
// bestehende Kaskade.
export interface BiennaleEventDetail {
  participants: EventParticipantCandidate[];
}

const INFO_BLOCK_PATTERN = /<div class="info">([\s\S]*?)<\/div>/g;
const LABEL_PATTERN = /<span class="label[^"]*">\s*(?:<p>([\s\S]*?)<\/p>)?\s*<\/span>/;
const ARTIST_NAME_PATTERN = /<span class="artist[^"]*">([\s\S]*?)<\/span>/g;

// Kreativ-/technisches Team ohne musikalische Mitwirkung auf der Bühne —
// dieselbe Grundidee wie CREATIVE_ROLES in staatsoperDetail.ts, an das hier
// beobachtete (englische) Rollenvokabular angepasst.
const NON_PERFORMING_ROLES =
  /composition|text|libretto|stage direction|scenographic|light design|costume design|anime design|technical|sound engineer|dramaturgy|choreography|video|set design|production/i;

export function parseBiennaleEventDetail(html: string): BiennaleEventDetail {
  const participants: EventParticipantCandidate[] = [];
  for (const match of html.matchAll(INFO_BLOCK_PATTERN)) {
    const block = match[1];
    const labelMatch = block.match(LABEL_PATTERN);
    const roleRaw = labelMatch?.[1]?.replace(/\s+/g, " ").replace(/:\s*$/, "").trim() || null;
    const names = [...block.matchAll(ARTIST_NAME_PATTERN)]
      .map((m) => m[1].replace(/\s+/g, " ").trim())
      .filter(Boolean);
    if (names.length === 0) continue;

    if (!roleRaw) {
      // Leeres Label → Ensemble (siehe Datei-Kommentar). Nur der erste Name
      // ist relevant, ein Ensemble-Eintrag hat hier nie mehrere Namen.
      participants.push({ name: names[0], profileUrl: null, role: null, type: "ensemble" });
      continue;
    }
    if (NON_PERFORMING_ROLES.test(roleRaw)) continue;
    const role = classifyRole(roleRaw);
    for (const name of names) {
      participants.push({ name, profileUrl: null, role, type: "person" });
    }
  }
  return { participants };
}

function classifyRole(roleRaw: string): "dirigent" | "chorleiter" | "solist" {
  if (/musical direction|conductor|dirigent/i.test(roleRaw)) return "dirigent";
  if (/chorus master|choir direction/i.test(roleRaw)) return "chorleiter";
  return "solist";
}
