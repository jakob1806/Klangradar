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
