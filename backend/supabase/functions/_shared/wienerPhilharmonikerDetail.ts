// Dritte venue-spezifische Hydration-Pipeline der Multi-City-Erweiterung,
// zweite für Wien (Nutzeranfrage: "mache venue-spezifische Hydration-Parser
// wie bei München"). Live gegen echtes HTML verifiziert (Deno, Event
// "1. Abonnementkonzert", Dirigent Tugan Sokhiev): einzige der bisher drei
// neuen Quellen mit einem ECHTEN, vollständigen Werkprogramm (Komponist +
// Werktitel inkl. Opuszahl) — "Programm"-Eintragsblock mit abwechselnden
// <span class="subline primary-color">Komponist</span>/<span
// class="subline primary-color cast-programm"><em>Werktitel</em></span>.
// Weitere "entry"-Blöcke (Dirigent/Orchester/Instrument als Subhead) liefern
// die Mitwirkenden.

export interface WienerPhilharmonikerParticipant {
  name: string;
  role: string | null;
  type: "person" | "ensemble";
}

export interface WienerPhilharmonikerWork {
  title: string;
  composerName: string | null;
  position: number;
}

export interface WienerPhilharmonikerDetail {
  participants: WienerPhilharmonikerParticipant[];
  works: WienerPhilharmonikerWork[];
}

const ENSEMBLE_ROLES = /^(Orchester|Chor|Ensemble)$/i;

export function parseWienerPhilharmonikerDetail(html: string): WienerPhilharmonikerDetail {
  const participants: WienerPhilharmonikerParticipant[] = [];
  const seenParticipant = new Set<string>();
  const works: WienerPhilharmonikerWork[] = [];

  for (const entryMatch of html.matchAll(/<div class="entry">([\s\S]*?)<\/div>/g)) {
    const entry = entryMatch[1];
    const subhead = cleanText(entry.match(/<span class="subhead">([\s\S]*?)<\/span>/)?.[1] ?? "");
    if (!subhead) continue;

    if (/^Programm$/i.test(subhead)) {
      // Abwechselnd Komponist (ohne "cast-programm"-Klasse) und Werktitel
      // (mit "cast-programm"-Klasse, in <em>) — siehe Modulkommentar.
      const composerAndWork = [...entry.matchAll(
        /<span class="subline primary-color">([\s\S]*?)<\/span>\s*<span class="subline primary-color cast-programm"><em>([\s\S]*?)<\/em><\/span>/g,
      )];
      for (const pair of composerAndWork) {
        const composerName = cleanText(pair[1]) || null;
        const title = cleanText(pair[2]);
        if (title) works.push({ title, composerName, position: works.length });
      }
      continue;
    }

    const name = cleanText(entry.match(/<span class="subline primary-color">([\s\S]*?)<\/span>/)?.[1] ?? "");
    if (!name) continue;
    const type: "person" | "ensemble" = ENSEMBLE_ROLES.test(subhead) ? "ensemble" : "person";
    // "Dirigent"/"Orchester" bleiben als kanonische Rollen erhalten, jedes
    // andere Subhead ist ein Instrument/Stimmfach (z.B. "Klavier", "Gesang")
    // — als role_label aussagekräftiger als ein generisches "solist".
    const role = /^Dirigent/i.test(subhead) ? "dirigent" : subhead;
    addParticipant({ name, role: type === "ensemble" ? null : role, type });
  }

  function addParticipant(participant: WienerPhilharmonikerParticipant) {
    const key = `${participant.type}:${participant.name.toLocaleLowerCase("de")}`;
    if (seenParticipant.has(key)) return;
    seenParticipant.add(key);
    participants.push(participant);
  }

  return { participants, works };
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
