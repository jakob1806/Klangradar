export interface StaatsoperParticipant {
  name: string;
  profileUrl: string | null;
  role: "komponist" | "dirigent" | "chorleiter" | "solist" | null;
  type: "person" | "ensemble";
  /** Rollen-/Instrumentenbezeichnung der Seite, z. B. "Don Ramiro". */
  roleLabel?: string | null;
}

export interface StaatsoperDetail {
  imageUrl: string | null;
  hasCastSection: boolean;
  participants: StaatsoperParticipant[];
  works: Array<{ title: string; composerName: string | null; position: number }>;
}

// 02.11.2026: auch zusammengesetzte Teamrollen („Mitarbeit Regie“, „Bühne und Kostüm“).
const CREATIVE_ROLES = /^(?:(?:Mitarbeit|Co-|Assistenz)\s*)?(?:Inszenierung|Regie|Bühne(?:nbild)?|Kostüme?|Kostümbild|Licht|Video|Dramaturgie|Choreographie|Choreografie|Produktionsleitung|Regieassistenz)(?:\s+(?:und|&)\s+(?:Bühne|Kostüme?|Licht|Video))?$/i;

// Live-Datenbestand bestätigt: fehlerhaft angelegte Ensembles wie "**Chor**"
// oder "**Choreographie**" (Markdown-Sternchen als Teil des gespeicherten
// Namens, letzteres zudem nur ein Zufallstreffer der /chor/i-Erkennung
// gegen "Choreographie") — Ursache im Detail nicht mehr nachvollziehbar
// (aktuell abgerufene Seiten liefern sauberes Markdown), aber diese Schicht
// verhindert es unabhängig davon: rohe Markdown-Marker entfernen, und
// Namen ablehnen, die nach dem Bereinigen nur noch ein bloßes Gattungswort
// sind statt eines konkreten Ensemblenamens ("Bayerischer Staatsopernchor"
// ist gültig, ein alleinstehendes "Chor" nicht).
function stripMarkdownEmphasis(raw: string): string {
  return raw.replace(/[*_~`]+/g, "").replace(/\s+/g, " ").trim();
}

const GENERIC_ENSEMBLE_NAMES = new Set([
  "chor", "chöre", "orchester", "ballett", "ensemble", "choreographie", "choreografie",
]);

function isPlausibleEnsembleName(name: string): boolean {
  return name.length >= 3 && !GENERIC_ENSEMBLE_NAMES.has(name.toLocaleLowerCase("de"));
}

export function parseStaatsoperDetail(markdown: string): StaatsoperDetail {
  const imageUrl = extractStaatsoperProductionImage(markdown);

  const castStart = markdown.indexOf("## Besetzung");
  const castEnd = castStart >= 0 ? markdown.indexOf("\n## ", castStart + 4) : -1;
  const cast = castStart >= 0 ? markdown.slice(castStart, castEnd >= 0 ? castEnd : undefined) : "";
  const participants: StaatsoperParticipant[] = [];
  const seen = new Set<string>();

  for (const line of cast.split("\n")) {
    const roleMatch = line.match(/^\*\s+\*\*([^*]+)\*\*/);
    if (roleMatch) {
      const rawRole = roleMatch[1];
      const label = rawRole.trim();
      if (CREATIVE_ROLES.test(label)) continue;
      const role = /Musikalische Leitung|Dirigent/i.test(label)
        ? "dirigent"
        : /^Chor(?:leitung)?$/i.test(label)
        ? "chorleiter"
        : "solist";
      // Mehrere Personen stehen auf der Staatsoper-Seite häufig in EINER
      // Instrumentenzeile. Alle Links lesen, nicht nur den ersten.
      //
      // Bug (Tölzer Knabenchor als "person" angelegt): die Staatsoper
      // verlinkt auch Ensembles (Chöre etc.) unter einer Rollen-Überschrift
      // wie "**Chor**" auf ihre eigene /biographien/-Profilseite — exakt
      // dasselbe Markup wie bei Solist:innen/Dirigent:innen. Ohne diese
      // Prüfung landete jeder verlinkte Name unabhängig vom Namen als
      // "person" (siehe unten den identischen Regex im plain-bullet-Zweig),
      // wurde also NIE durch resolveEnsembles()/resolve_ensemble_entities
      // aufgelöst und legte stattdessen einen eigenen persons-Datensatz an.
      for (const link of line.matchAll(/\[([^\]]+)\]\((https:\/\/www\.staatsoper\.de\/biographien\/[^)]+)\)/g)) {
        const name = stripMarkdownEmphasis(link[1]);
        if (!name || /^(N\.N\.?|TBA|TBD)$/i.test(name)) continue;
        if (/(?:orchester|chor|ensemble|ballett)/i.test(name) && isPlausibleEnsembleName(name)) {
          add({ name, profileUrl: link[2], role: null, type: "ensemble" });
        } else {
          // Nutzerfeedback 30.10.2026: Besetzung der Staatsoper zeigte nur
          // Namen ohne Partie — die Partie ("Tosca", "Violine") geht jetzt
          // als role_label mit.
          const roleLabel = role === "dirigent" ? "Musikalische Leitung" : role === "chorleiter" ? "Chor" : label;
          add({ name, profileUrl: link[2], role, type: "person", roleLabel });
        }
      }
      continue;
    }

    const plain = line.match(/^\*\s+([^*\[].+?)\s*$/);
    if (plain) {
      const ensembleName = stripMarkdownEmphasis(plain[1]);
      if (/(?:orchester|chor|ensemble|ballett)/i.test(ensembleName) && isPlausibleEnsembleName(ensembleName)) {
        add({ name: ensembleName, profileUrl: null, role: null, type: "ensemble" });
      }
    }
  }

  function add(participant: StaatsoperParticipant) {
    const key = `${participant.type}:${participant.name.toLocaleLowerCase("de")}`;
    if (seen.has(key)) return;
    seen.add(key);
    participants.push(participant);
  }

  return {
    imageUrl,
    hasCastSection: castStart >= 0,
    participants,
    works: parseWorks(markdown, castStart),
  };
}

export function extractStaatsoperProductionImage(markdown: string): string | null {
  // Das echte Hero-Bild steht vor den Tabs/Stückdetails. Danach folgen
  // Handlungsgalerien und Empfehlungen, die nicht als Eventcover taugen.
  const end = markdown.search(/\n(?:\*\s+\[Stück-Details|## Besetzung|\*\s+Programm Mehr laden)/i);
  const header = end >= 0 ? markdown.slice(0, end) : markdown.slice(0, 20_000);
  const candidates = [...header.matchAll(
    /!\[Image\s+\d+(?::[^\]]*)?\]\((https:\/\/www\.staatsoper\.de\/(?:media|fileadmin)\/[^)]+)\)/gi,
  )].map((match) => match[1]);
  return candidates.find((url) => !/(?:bmw|logo|partner|unicredit|zeitstrahl|placeholder|dummy)/i.test(url)) ?? null;
}

function parseWorks(markdown: string, castStart: number) {
  const programMarker = markdown.search(/\*\s+Programm Mehr laden/i);
  const works: Array<{ title: string; composerName: string | null; position: number }> = [];

  if (programMarker >= 0 && castStart > programMarker) {
    const section = markdown.slice(programMarker, castStart);
    let composerName: string | null = null;
    for (const rawLine of section.split("\n")) {
      const line = rawLine.trim();
      const composer = line.match(/^\*\*([^*]+)\*\*$/);
      if (composer) {
        composerName = composer[1].trim();
        continue;
      }
      const work = line.match(/^_([^_]+)_\s*(.*)$/);
      if (!work) continue;
      const title = `${work[1]} ${work[2]}`.replace(/\s+/g, " ").trim();
      if (title) works.push({ title, composerName, position: works.length });
    }
  }

  // Oper/Ballett-Seiten haben keine separate Programmliste: das aufgeführte
  // Werk steht als Seitentitel plus expliziter Komponistenzeile bereit.
  if (works.length === 0) {
    const title = markdown.match(/^#\s+(.+)$/m)?.[1]?.trim();
    const composer = markdown.match(/\*\*Komponist\s+([^.*]+?)(?:\.|\*\*)/i)?.[1]?.trim() ?? null;
    const isBallet = /\n\s*Ballett\s*\n/i.test(markdown);
    if (title && (composer || isBallet)) works.push({ title, composerName: composer, position: 0 });
  }
  return works;
}

/** Sperr-/Wartungsseite statt Spielplan (Reader liefert dann trotzdem 200). */
export function isBlockedReaderPage(text: string): boolean {
  return /Target URL returned error 40[13]|^Title: Just a moment/m.test(text) ||
    (/HOFFENTLICH KURZES INTERMEZZO/i.test(text) && !/Weitere Informationen zu/.test(text));
}

/** Besetzung direkt aus dem HTML der Detailseite (02.11.2026). Der
 * Markdown-Modus des Readers liefert seit Kurzem nur noch die Rollen ohne
 * Namen („**Mime**“), das HTML enthält sie weiterhin:
 * `<ul class="cast-list"><li><strong>Mime</strong>…<a href="/biographien/…">Matthias Klink</a>`. */
export function parseStaatsoperCastHtml(html: string): StaatsoperParticipant[] {
  const participants: StaatsoperParticipant[] = [];
  const seen = new Set<string>();
  // Tags per Zeichen-Schleife entfernen, Entities danach, „&amp;“ zuletzt
  // (kein doppeltes Entschlüsseln, keine „<script“-Reste; CodeQL).
  const decode = (t: string) => {
    let out = "";
    let inTag = false;
    for (const ch of t) {
      if (ch === "<") inTag = true;
      else if (ch === ">") inTag = false;
      else if (!inTag) out += ch;
    }
    return out.replace(/&#39;|&#039;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
  };
  for (const list of html.matchAll(/<ul class="cast-list">([\s\S]*?)<\/ul>/g)) {
    for (const item of list[1].matchAll(/<li><strong>([\s\S]*?)<\/strong>([\s\S]*?)<\/li>/g)) {
      const label = decode(item[1]);
      if (!label || CREATIVE_ROLES.test(label)) continue;
      const role = /Musikalische Leitung|Dirigent/i.test(label) ? "dirigent" : /^Chor(?:leitung)?$/i.test(label) ? "chorleiter" : "solist";
      const links = [...item[2].matchAll(/<a href="(\/biographien\/[^"]+)">([\s\S]*?)<\/a>/g)];
      const plain = links.length === 0 ? decode(item[2]) : "";
      for (const link of links) {
        const name = stripMarkdownEmphasis(decode(link[2]));
        if (!name || /^(N\.N\.?|TBA|TBD)$/i.test(name)) continue;
        const profileUrl = `https://www.staatsoper.de${link[1]}`;
        const isEnsemble = /(?:orchester|chor|ensemble|ballett)/i.test(name) && isPlausibleEnsembleName(name);
        const key = `${isEnsemble ? "ensemble" : "person"}:${name.toLocaleLowerCase("de")}`;
        if (seen.has(key)) continue;
        seen.add(key);
        participants.push(isEnsemble
          ? { name, profileUrl, role: null, type: "ensemble" }
          : { name, profileUrl, role, type: "person", roleLabel: role === "dirigent" ? "Musikalische Leitung" : role === "chorleiter" ? "Chor" : label });
      }
      // Reine Textzeile ohne Link, z. B. „Bayerisches Staatsorchester“.
      if (plain && /(?:orchester|chor|ensemble|ballett)/i.test(plain) && isPlausibleEnsembleName(plain)) {
        const key = `ensemble:${plain.toLocaleLowerCase("de")}`;
        if (!seen.has(key)) { seen.add(key); participants.push({ name: plain, profileUrl: null, role: null, type: "ensemble" }); }
      }
    }
    // Ensemble-Zeilen ohne <strong> (eigene <li>-Form)
    for (const item of list[1].matchAll(/<li>(?!<strong>)([\s\S]*?)<\/li>/g)) {
      const name = decode(item[1]);
      if (name && /(?:orchester|chor|ensemble|ballett)/i.test(name) && isPlausibleEnsembleName(name)) {
        const key = `ensemble:${name.toLocaleLowerCase("de")}`;
        if (!seen.has(key)) { seen.add(key); participants.push({ name, profileUrl: null, role: null, type: "ensemble" }); }
      }
    }
  }
  return participants;
}
