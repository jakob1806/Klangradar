// Schneidet aus dem bereinigten Volltext einer Veranstaltungsseite den
// eigentlichen Programmblock heraus. Der allgemeine Event-Extraktor bekommt
// oft mehrere tausend Zeichen Navigation, Marketing und Ticketinformationen;
// ein klar abgegrenzter Werkblock ist für eine konservative, vollständige
// Extraktion wesentlich zuverlässiger.

const START_HEADING = /^(programm|program|werke|repertoire)\s*:? *$/i;
const STOP_HEADING =
  /^(mitwirkende|besetzung|künstler(?:innen)?|artists?|tickets?|termine|weitere termine|ähnliche (?:konzerte|veranstaltungen)|veranstaltungsort|spielstätte|preise?|kontakt|newsletter|biografie|beschreibung)\s*:? *$/i;

export function extractProgramSection(pageText: string | null): string | null {
  if (!pageText) return null;

  const lines = pageText
    .split("\n")
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);
  const start = lines.findIndex((line) => START_HEADING.test(line));
  if (start < 0) return null;

  const result: string[] = [];
  for (const line of lines.slice(start + 1)) {
    if (STOP_HEADING.test(line)) break;
    result.push(line);
    if (result.join("\n").length >= 3500) break;
  }

  // Eine einzelne generische Zeile wie „Werke von Mozart“ ist kein
  // strukturiertes Programm. Mindestens zwei Inhaltszeilen verhindern,
  // dass die Spezialextraktion Werbetext als konkrete Werkliste ausgibt.
  return result.length >= 2 ? result.join("\n").slice(0, 3500) : null;
}

function normalized(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .toLowerCase();
}

/** Liefert bei offiziellen Listen im Muster „Komponist\nWerk“ den direkt
 * zugehörigen Namen und die Pausenposition. Dies ist bewusst keine freie
 * Werk-Erkennung, sondern validiert ausschließlich ein bereits vom Modell
 * erkanntes Werk gegen seine exakte Quellzeile. */
export function findProgramContextForWork(
  programSection: string,
  workTitle: string,
): { composerName: string | null; afterIntermission: boolean } | null {
  const lines = programSection.split("\n").map((line) => line.trim()).filter(
    Boolean,
  );
  const wanted = normalized(workTitle);
  const index = lines.findIndex((line) => {
    const candidate = normalized(line);
    return candidate.length >= 5 &&
      (candidate.includes(wanted) || wanted.includes(candidate));
  });
  if (index < 0) return null;

  const previous = index > 0 ? lines[index - 1].replace(/,+$/, "").trim() : "";
  const personName =
    /^[\p{L}.'’\-]+(?:\s+[\p{L}.'’\-]+){1,4}$/u.test(previous) &&
      !/^(pause|programm|program)$/i.test(previous)
      ? previous
      : null;
  const pauseIndex = lines.findIndex((line) => /^pause$/i.test(line));
  return {
    composerName: personName,
    afterIntermission: pauseIndex >= 0 && index > pauseIndex,
  };
}
