// Zweite venue-spezifische Hydration-Pipeline der Multi-City-Erweiterung,
// erste für Wien (Nutzeranfrage: "mache venue-spezifische Hydration-Parser
// wie bei München"). Live gegen echtes HTML verifiziert (Deno, Event "Die
// Fledermaus - Singalong"): die Produktionsseite liefert serverseitig
// gerendert sowohl die Besetzung (Opernrolle -> Sänger:in) als auch das
// künstlerische Team (Dirigent etc.), KEIN separates AJAX nötig (anders als
// Komische Oper Berlin).
//
// Zwei unterschiedliche Markup-Muster auf derselben Seite:
// 1. Besetzung: <dt class="…role">Opernrolle</dt><dd class="…name">
//    <a>Vorname <span>Nachname</span></a></dd>
// 2. Künstlerisches Team: <span class="role">Funktion</span>
//    <span class="name">…Vorname <span>Nachname</span>…</span> (teils mit
//    <a>-Link, teils reiner Text ohne Link).
//
// Bewusst wird die Opernrolle selbst (z.B. "Gabriel von Eisenstein,
// Rentier") als role_label gespeichert statt eines generischen "solist" —
// das ist die konkretere, für Nutzer:innen sichtbar nützlichere Information
// (analog zur bereits bestehenden Redaktionsfunktion für freie
// event-spezifische role_label-Werte). Kein separates Werk-/Programm-
// verzeichnis auf dieser Seite (das Stück IST das Event) — deshalb wie
// hydrate-komischeoperberlin-events nur event_participants.

export interface VolksoperParticipant {
  name: string;
  profileUrl: string | null;
  role: string | null;
  type: "person" | "ensemble";
}

const CREATIVE_ROLES_TO_SKIP =
  /^(Nach einer Inszenierung|Inszenierung|Regie|B(?:ü|u)hnenbild|Kost(?:ü|u)me?|Licht|Choreografie|Choreographie|Dramaturgie|B(?:ü|u)hne)/i;
const CONDUCTOR_ROLE = /^Dirigent/i;
const ENSEMBLE_NAME = /(?:orchester|chor|ensemble|ballett)/i;

export function parseVolksoperDetail(html: string): VolksoperParticipant[] {
  const participants: VolksoperParticipant[] = [];
  const seen = new Set<string>();

  // 1. Besetzung (Opernrolle -> Sänger:in).
  const castRe = /<dt[^>]*class="[^"]*\brole\b[^"]*"[^>]*>([\s\S]*?)<\/dt>\s*<dd[^>]*class="[^"]*\bname\b[^"]*"[^>]*>([\s\S]*?)<\/dd>/g;
  for (const m of html.matchAll(castRe)) {
    const roleLabel = cleanText(m[1]);
    const name = cleanText(m[2]);
    if (!roleLabel || !name) continue;
    add({ name, profileUrl: extractHref(m[2]), role: roleLabel, type: nameLooksLikeEnsemble(name) ? "ensemble" : "person" });
  }

  // 2. Künstlerisches Team (nur Dirigent:in wird übernommen, der Rest sind
  // Regie/Bühnenbild/Kostüme — bewusst wie bei Staatsoper/Komische Oper
  // Berlin nicht als "Mitwirkende" im musikalischen Sinn gezählt).
  const teamRe = /<span[^>]*class="[^"]*\brole\b[^"]*"[^>]*>([\s\S]*?)<\/span>\s*<span[^>]*class="[^"]*\bname\b[^"]*"[^>]*>([\s\S]*?)<\/span>/g;
  for (const m of html.matchAll(teamRe)) {
    const roleLabel = cleanText(m[1]);
    if (!roleLabel || CREATIVE_ROLES_TO_SKIP.test(roleLabel)) continue;
    if (!CONDUCTOR_ROLE.test(roleLabel)) continue;
    const name = cleanText(m[2]);
    if (!name) continue;
    add({ name, profileUrl: extractHref(m[2]), role: "dirigent", type: "person" });
  }

  function add(participant: VolksoperParticipant) {
    const key = `${participant.type}:${participant.name.toLocaleLowerCase("de")}`;
    if (seen.has(key)) return;
    seen.add(key);
    participants.push(participant);
  }

  return participants;

  function nameLooksLikeEnsemble(name: string): boolean {
    return ENSEMBLE_NAME.test(name);
  }
}

function extractHref(fragment: string): string | null {
  const match = fragment.match(/href="([^"]+)"/);
  if (!match) return null;
  return match[1].startsWith("http") ? match[1] : `https://www.volksoper.at${match[1]}`;
}

function cleanText(fragment: string): string {
  return decodeEntities(fragment.replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

function decodeEntities(raw: string): string {
  return raw
    .replace(/&amp;/g, "&")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&auml;/g, "ä").replace(/&ouml;/g, "ö").replace(/&uuml;/g, "ü").replace(/&szlig;/g, "ß")
    .replace(/&Auml;/g, "Ä").replace(/&Ouml;/g, "Ö").replace(/&Uuml;/g, "Ü");
}
