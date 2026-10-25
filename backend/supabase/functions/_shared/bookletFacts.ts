// Erstellt von Claude Code (25.10.2026): Werkangaben aus Programmheften.
// Programmhefte nennen auf der Programmseite je Werk Dauer und Satzfolge
// ("Symphonie Nr. 39 g-Moll Hob. I:39 (21’) 1. Allegro assai 2. Andante …")
// und enthalten Einführungstexte. Daraus: Satzfolge, Dauer und – für Werke
// ohne Wikipedia-Einführung – ein kurzer, zitierter Auszug (max. ~700
// Zeichen, mit Link auf das Heft).
import { getDocumentProxy } from "npm:unpdf@0.12.1";

export interface BookletWorkFacts {
  movements: string[];
  durationMinutes: number | null;
  excerpt: string | null;
}

const COMMON = new Set(["über", "und", "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "mit", "von", "zu", "zur", "zum", "im", "in", "auf", "aus", "als", "an", "am", "bei", "für", "nach", "sich", "nicht", "auch", "wie", "so", "es", "er", "sie", "ist", "war", "hat", "wird"]);

/** PDF → Text; am Zeilenende getrennte Wörter (weiches Trennzeichen ohne
 * sichtbaren Strich) werden wieder zusammengesetzt, wenn das hintere
 * Bruchstück im Heft sonst nicht als eigenes Wort vorkommt. */
export async function pdfText(bytes: Uint8Array): Promise<string> {
  const pdf = await getDocumentProxy(bytes);
  const lines: string[] = [];
  for (let p = 1; p <= Math.min(pdf.numPages, 60); p++) {
    // deno-lint-ignore no-explicit-any
    const items = (await (await pdf.getPage(p)).getTextContent()).items as any[];
    let line = "";
    for (const item of items) {
      line += item.str;
      if (item.hasEOL) { lines.push(line); line = ""; }
    }
    if (line) lines.push(line);
  }
  // Wortschatz nur aus dem Zeileninneren (Bruchstücke am Zeilenrand würden
  // sich sonst selbst als "bekanntes Wort" bestätigen).
  const vocab = new Set(lines.flatMap((l) => l.trim().toLowerCase().split(/[^a-zäöüß]+/).filter(Boolean).slice(1, -1)));
  let out = "";
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    const head = out.match(/([A-Za-zÄÖÜäöüß]+)$/)?.[1] ?? "";
    const tail = line.match(/^([a-zäöüß]+)/)?.[1] ?? "";
    const joined = out.endsWith("-") ? true
      : head && tail && !COMMON.has(head.toLowerCase()) && !COMMON.has(tail) &&
        (vocab.has((head + tail).toLowerCase()) || (!vocab.has(head.toLowerCase()) && !vocab.has(tail)));
    out = joined ? out.replace(/-$/, "") + line : out + (out ? " " : "") + line;
  }
  return out.replace(/\s+/g, " ");
}

function norm(value: string): string {
  return value.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}

const STOP = new Set(["konzert", "symphonie", "sinfonie", "fur", "und", "orchester", "nr", "op", "der", "die", "das", "des", "aus", "zu", "dur", "moll", "in", "the", "of", "and", "kleines", "grosses", "oper", "hob", "kv", "bwv", "wab"]);

/** Markante Wörter eines Werktitels (ohne Gattung/Füllwörter). */
function titleKeys(title: string): string[] {
  return norm(title).replace(/[»«„“"()',.:;–-]/g, " ").split(/\s+/).filter((w) => w.length > 2 && !STOP.has(w) && !/^\d/.test(w));
}

function hasWord(haystack: string, word: string): boolean {
  // Auch Genitiv/Adjektiv: "Ravels", "Haydns".
  return new RegExp(`(^|[^a-z0-9])${word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}s?([^a-z0-9]|$)`).test(haystack);
}

const GENRE = /(symphonie|sinfonie|konzert|ouverture|suite|quartett|sonate|messe|requiem)/;
const META = /†|\*\s?\d|Entstehungszeit|Uraufführung am|unter der Leitung|^\d/;

const NUM = String.raw`(?:\d{1,2}|[IVX]{1,4})\.`;

/** Satzliste nach der Dauerangabe: "1. Allegro assai 2. Andante …". Der
 * letzte Satz endet vor dem nächsten Namen (zwei großgeschriebene Wörter),
 * "Pause", "»" oder einer Klammer. */
function parseMovements(after: string): string[] {
  const out: string[] = [];
  const re = new RegExp(`^\\s*(${NUM})\\s+`);
  let rest = after;
  for (let n = 0; n < 12; n++) {
    const m = rest.match(re);
    if (!m) break;
    rest = rest.slice(m[0].length);
    const next = rest.search(new RegExp(`\\s${NUM}\\s`));
    let item = next >= 0 ? rest.slice(0, next) : rest;
    const stop = item.search(/\s(?=Pause\b|»|\(|[A-ZÄÖÜ][a-zäöü]+\s[A-ZÄÖÜ][a-zäöü]+\s[A-ZÄÖÜ»])/);
    const ended = stop >= 0;
    if (ended) item = item.slice(0, stop);
    item = item.trim();
    if (!item || item.length > 90) break;
    out.push(`${m[1]} ${item}`);
    if (ended || next < 0) break;
    rest = rest.slice(next);
  }
  return out;
}

export function factsForWork(text: string, workTitle: string, composer: string | null, otherSurnames: string[] = []): BookletWorkFacts {
  const flat = text.replace(/\s+/g, " ");
  const lower = norm(flat);
  const surname = norm((composer ?? "").split(/\s+/).pop() ?? "");
  const keys = titleKeys(workTitle);
  const number = workTitle.match(/\bNr\.\s*(\d+)/)?.[1];
  const quoted = norm(workTitle.match(/»([^«]+)«/)?.[1] ?? "").split(/\s+/)[0];

  // 1) Programmseite: Komponist:in, dann Titel, dann "(21’)" und Satzliste.
  let movements: string[] = [];
  let durationMinutes: number | null = null;
  let from = 0;
  while (surname && (from = lower.indexOf(surname, from)) !== -1) {
    const window = lower.slice(from, from + 240);
    const anchor = number ? window.search(new RegExp(`nr\\.\\s*${number}\\b`)) : quoted ? window.indexOf(quoted) : keys.length ? Math.max(...keys.map((k) => window.indexOf(k))) : 0;
    if (anchor >= 0) {
      const tail = flat.slice(from + anchor, from + anchor + 200);
      const dur = tail.match(/\((\d{1,3})\s*[’'′]\s*\)/);
      // Dauer muss direkt zum Titel gehören (kein anderer Komponist dazwischen).
      if (dur && !otherSurnames.some((s) => norm(tail.slice(0, dur.index)).includes(norm(s)))) {
        durationMinutes = Number(dur[1]);
        movements = parseMovements(flat.slice(from + anchor + (dur.index ?? 0) + dur[0].length, from + anchor + 1200));
        break;
      }
    }
    from += surname.length;
  }

  // 2) Einführungstext: Sätze ab der ersten Nennung des Werks, bis ein
  //    anderes Werk/eine andere Person auftaucht.
  let excerpt: string | null = null;
  const sentences = flat.split(/(?<=[.!?])\s+(?=[A-ZÄÖÜ„»])/);
  const genre = norm(workTitle).match(GENRE)?.[1];
  const mentions = (s: string) => {
    const n = norm(s);
    if (quoted) return hasWord(n, quoted);
    return !!surname && hasWord(n, surname) && (keys.some((k) => hasWord(n, k)) || (!!genre && n.includes(genre.slice(0, 6))));
  };
  for (let i = 0; i < sentences.length; i++) {
    if (sentences[i].length < 60 || sentences[i].length > 600 || !mentions(sentences[i]) || META.test(sentences[i]) || /\(\d{1,3}\s*[’'′]\)/.test(sentences[i])) continue;
    const picked: string[] = [];
    for (let j = i; j < sentences.length && picked.join(" ").length < 600; j++) {
      const s = norm(sentences[j]);
      if (j > i && (otherSurnames.some((o) => hasWord(s, norm(o))) || META.test(sentences[j]))) break;
      picked.push(sentences[j]);
    }
    // Seitenkopf/Lebensdaten vor dem Essay abschneiden ("Mai 1809 in Wien 9 …",
    // "21 Traumverloren Franz Schreker: »Nachtstück« Mit …").
    const text = picked.join(" ")
      .replace(/^(?:[A-ZÄÖÜ][a-zäöü]+\s+\d{4}\s+in\s+[A-ZÄÖÜ][\wäöü-]+\s+)?\d{1,3}\s+/, "")
      .replace(/^(?:[A-ZÄÖÜ][\wäöü-]+(?:\s+[A-ZÄÖÜa-zäöü][\wäöü-]+){0,6}\s+)?[A-ZÄÖÜ][\wäöü.]+(?:\s+[A-ZÄÖÜ][\wäöü.-]+){0,3}:\s+[^.]{0,80}?(?=\s[A-ZÄÖÜ][a-zäöü]+\s)/, "")
      .trim();
    if (text.length > 160) { excerpt = text.length > 720 ? text.slice(0, 720).replace(/\s+\S*$/, "") + " …" : text; break; }
  }
  return { movements: movements.length >= 2 ? movements : [], durationMinutes, excerpt };
}
