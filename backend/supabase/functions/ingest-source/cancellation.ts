// Erkennt im Titel einer Quelle, dass eine Veranstaltung abgesagt oder
// verschoben wurde. Viele Häuser markieren das nur im Titel ("ABGESAGT: Julia
// Kleiter / Julian Prégardien / Sir András Schiff", Laeiszhalle 05.10.2026),
// ohne eigenes Statusfeld — der Scraper legte solche Events bisher als normal
// geplant an.

export type TitleStatus = "cancelled" | "postponed";

// Marker am Titelanfang oder in Klammern/Pausenzeichen davor, z. B.
// "ABGESAGT: …", "[Abgesagt] …", "(entfällt) …", "Abgesagt – …", "CANCELLED …".
const CANCELLED = /^\s*[\[(*]?\s*(?:abgesagt|entfällt|entfaellt|fällt\s+aus|faellt\s+aus|cancel+ed|annulliert|annulé)\b/i;
const POSTPONED = /^\s*[\[(*]?\s*(?:verschoben|verlegt|postponed|reporté)\b/i;
// "… (ABGESAGT)" / "… – abgesagt" am Titelende.
const CANCELLED_SUFFIX = /[\s\-–—:(\[]+(?:abgesagt|entfällt|cancel+ed)\s*[)\]]?\s*$/i;

export function detectTitleStatus(title: string): TitleStatus | null {
  if (CANCELLED.test(title) || CANCELLED_SUFFIX.test(title)) return "cancelled";
  if (POSTPONED.test(title)) return "postponed";
  return null;
}

// Absage/Verschiebung im Beschreibungstext ("Das Konzert muss leider
// abgesagt werden", "Die Veranstaltung entfällt", "wird auf … verschoben").
// Bewusst nur ganze Aussagen, damit Hinweise wie "Bei Absage erstatten wir …"
// nicht anschlagen.
const TEXT_CANCELLED = /\b(?:konzert|veranstaltung|vorstellung|aufführung|abend|termin)\s+(?:ist|wurde|muss|musste|wird)\s+(?:leider\s+)?(?:krankheitsbedingt\s+)?(?:abgesagt|ersatzlos\s+gestrichen)|\b(?:konzert|veranstaltung|vorstellung|aufführung|termin)\s+(?:entfällt|fällt\s+(?:leider\s+)?aus|findet\s+(?:leider\s+)?nicht\s+statt)|\bthis\s+(?:concert|event|performance)\s+(?:has\s+been|is)\s+cancel+ed/i;
const TEXT_POSTPONED = /\b(?:konzert|veranstaltung|vorstellung|aufführung|termin)\s+(?:ist|wurde|muss|wird)\s+(?:leider\s+)?(?:auf\s+.{1,40}?\s+)?(?:verschoben|verlegt)/i;

export function detectTextStatus(text: string | null | undefined): TitleStatus | null {
  if (!text) return null;
  if (TEXT_CANCELLED.test(text)) return "cancelled";
  if (TEXT_POSTPONED.test(text)) return "postponed";
  return null;
}

/** Titel hat Vorrang, dann Beschreibung. */
export function detectEventStatus(title: string, description?: string | null): TitleStatus | null {
  return detectTitleStatus(title) ?? detectTextStatus(description);
}
