// Keine Wortgrenzen: deutsche Komposita wie "Symphonieorchester" oder
// "Staatsopernchor" sind gerade besonders starke Ensemble-Signale.
const ENSEMBLE_MARKERS = /(chor|choir|orchester|orchestra|ensemble|philharmoni|philharmonic|sinfoniker|symphoniker|symphony|quartett|quartet|quintett|quintet|trio|band|consort|solisten|singers|players|kapelle|collegium|akademie|academy)/i;
const NON_ENTITY_TEXT = /\b(ticket(?:verkauf|s)?|abendkasse|vorverkauf|einlass|karten|reservierung|buchung|erhältlich|preis|euro|beginn|veranstalter|weitere informationen|mehr erfahren|jetzt buchen|hier klicken|ausverkauft)\b/i;
const PERSON_CONNECTORS = new Set(["de", "del", "della", "di", "da", "van", "von", "zu", "zur", "la", "le"]);

export interface EnsembleNameAssessment {
  safe: boolean;
  cleaned: string;
  reason: string | null;
}

/** Harte Schranke vor jeder automatischen Ensemble-Anlage. Sie akzeptiert
 * eindeutige Gruppennamen, lehnt Fließ-/Tickettexte ab und hält Namen, die
 * wie einzelne Personen aussehen, zur manuellen Prüfung zurück. */
export function assessEnsembleName(rawName: string): EnsembleNameAssessment {
  const cleaned = rawName
    .replace(/<[^>]+>/g, " ")
    .replace(/[*_~`]+/g, "")
    .replace(/\s+/g, " ")
    .trim();
  const words = cleaned.split(/\s+/).filter(Boolean);
  if (cleaned.length < 3) return { safe: false, cleaned, reason: "zu kurz" };
  if (NON_ENTITY_TEXT.test(cleaned)) return { safe: false, cleaned, reason: "Ticket- oder Informationstext" };
  if (/^[a-zäöüß]/.test(cleaned)) return { safe: false, cleaned, reason: "beginnt wie Fließtext" };
  if (words.length > 10 || /[.!?;:]$/.test(cleaned)) return { safe: false, cleaned, reason: "wahrscheinlich Fließtext" };
  if (ENSEMBLE_MARKERS.test(cleaned)) return { safe: true, cleaned, reason: null };
  if (/^[A-ZÄÖÜ0-9]{2,8}$/.test(cleaned) || words.length === 1) {
    return { safe: false, cleaned, reason: "uneindeutiger Gruppenname" };
  }
  const looksLikePerson = words.length >= 2 && words.length <= 5 && words.every((word) =>
    PERSON_CONNECTORS.has(word.toLocaleLowerCase("de")) || /^[A-ZÄÖÜ][\p{L}'’.-]+$/u.test(word)
  );
  if (looksLikePerson) return { safe: false, cleaned, reason: "sieht wie ein Personenname aus" };
  return { safe: false, cleaned, reason: "kein eindeutiges Ensemble-Signal" };
}

export function isObviousNonEnsembleText(rawName: string): boolean {
  const assessment = assessEnsembleName(rawName);
  return !assessment.safe && assessment.reason !== "uneindeutiger Gruppenname";
}
