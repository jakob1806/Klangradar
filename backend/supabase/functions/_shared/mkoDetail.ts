import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";

// Live-Struktur einer Münchener-Kammerorchester-Konzert-Detailseite
// (m-k-o.eu/event-detail/<id>/<slug>/, verifiziert am 2026-08-14 gegen
// .../event-detail/2673/26---27%20Abo%202/ und .../3906/...):
//
//   <h4><b>12.11.2026, 20 Uhr Prinzregententheater</b></h4>
//   <p>Sarah Aristidou, Sopran<br>Bas Wiegers, Dirigent</p>
//   <h4><b>Programm</b></h4>...
//
// Der einzige <p>-Block direkt vor der "Programm"-Überschrift enthält die
// Besetzung, eine Zeile pro <br>, Format "Name, Rolle" — kein eigener
// Abschnitts-Marker davor (anders als bei Gasteig/Staatsoper), deshalb
// Ankerpunkt am stabilen "Programm"-Heading statt an einem eigenen
// "Mitwirkende"-Label, das es hier nicht gibt. Kein Eventfoto nötig —
// og:image ist auf m-k-o.eu bereits sauber gesetzt (Fotograf im
// Dateinamen, z.B. "...credit-Daniel-Delang..."), wird schon über die
// bestehende coverImageDetection.ts-Kaskade gefunden. Keine Bio-Links für
// einzelne Mitwirkende auf dieser Seite.
export interface MkoEventDetail {
  participants: EventParticipantCandidate[];
}

const PERFORMER_BLOCK_PATTERN = /<p>([\s\S]*?)<\/p>\s*<h4[^>]*><b>Programm<\/b><\/h4>/i;
const LINE_SPLIT_PATTERN = /<br\s*\/?>/i;

const RESIDENT_ENSEMBLE = "Münchener Kammerorchester";

export function parseMkoEventDetail(html: string): MkoEventDetail {
  const block = html.match(PERFORMER_BLOCK_PATTERN)?.[1];
  if (!block) return { participants: [] };

  const participants: EventParticipantCandidate[] = [];
  for (const rawLine of block.split(LINE_SPLIT_PATTERN)) {
    const text = stripTags(rawLine).replace(/\s+/g, " ").trim();
    if (!text) continue;
    const commaIndex = text.indexOf(",");
    if (commaIndex < 0) continue; // kein Rollen-Komma → keine auswertbare Zeile
    const name = text.slice(0, commaIndex).trim();
    const roleRaw = text.slice(commaIndex + 1).trim();
    if (!name || !roleRaw) continue;
    participants.push({ name, profileUrl: null, role: classifyRole(roleRaw), type: "person" });
  }

  if (participants.length > 0) {
    participants.push({ name: RESIDENT_ENSEMBLE, profileUrl: null, role: null, type: "ensemble" });
  }

  return { participants };
}

function classifyRole(roleRaw: string): "dirigent" | "chorleiter" | "solist" {
  if (/dirigent/i.test(roleRaw)) return "dirigent";
  if (/chorleit/i.test(roleRaw)) return "chorleiter";
  return "solist";
}

function stripTags(value: string): string {
  return value.replace(/<[^>]+>/g, " ");
}
