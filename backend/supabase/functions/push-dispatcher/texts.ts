// Erstellt von Claude Code. Texte der Push-Mitteilungen.
// KI formuliert aus festen Fakten (kurz, persönlich, wechselnder Ton);
// validateText() verwirft Texte mit erfundenen Zahlen/Uhrzeiten, Links oder
// Überlänge. Ohne KI oder bei Ablehnung: wechselnde Vorlagen.
import type { Candidate } from "./select.ts";

export interface PushText {
  title: string;
  body: string;
}

// deno-lint-ignore no-explicit-any
type Facts = Record<string, any>;

function fmt(iso: string | undefined, opts: Intl.DateTimeFormatOptions): string {
  if (!iso) return "";
  return new Intl.DateTimeFormat("de-DE", { ...opts, timeZone: "Europe/Berlin" }).format(new Date(iso));
}

/** Ergänzt menschenlesbare Datums-/Zeitangaben, die die KI verwenden darf. */
export function enrichFacts(c: Candidate): Facts {
  const f: Facts = { ...c.facts };
  if (f.start) {
    f.time = fmt(f.start, { hour: "2-digit", minute: "2-digit" });
    f.day = fmt(f.start, { weekday: "long" });
    f.date = fmt(f.start, { day: "numeric", month: "long" });
  }
  if (Array.isArray(f.events)) {
    f.events = f.events.slice(0, 3).map((e: Facts) => ({ ...e, date: fmt(e.start, { day: "numeric", month: "long" }) }));
  }
  delete f.slug;
  delete f.image_url;
  return f;
}

/** Einfacher, stabiler Hash für die Auswahl einer Vorlagen-Variante. */
function pick<T>(key: string, options: T[]): T {
  let h = 0;
  for (const ch of key) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return options[h % options.length];
}

export function templateText(c: Candidate): PushText {
  const f = enrichFacts(c);
  const name = f.first_name ? `${f.first_name}, ` : "";
  switch (c.kind) {
    case "new_followed": {
      const who = (f.followed ?? []).slice(0, 2).join(" und ") || "Von dir Gefolgte";
      const first = f.events?.[0];
      return pick(c.dedupe_key, [
        { title: `Neu von ${who}`, body: f.count > 1 ? `${f.count} neue Termine, darunter „${first?.title}“ am ${first?.date}.` : `„${first?.title}“ am ${first?.date} – frisch angekündigt.` },
        { title: "Gerade angekündigt", body: `${who}: ${f.count > 1 ? `${f.count} neue Konzerte` : `„${first?.title}“`} bei Klangradar.` },
        { title: `${who} kommt wieder`, body: `${first?.date}${first?.venue ? `, ${first.venue}` : ""}: „${first?.title}“.` },
      ]);
    }
    case "almost_sold_out":
      return pick(c.dedupe_key, [
        { title: "Nur noch wenige Karten", body: `„${f.title}“ am ${f.day} ist fast ausverkauft.` },
        { title: `Fast weg: ${f.title}`, body: `${f.date}${f.venue ? ` · ${f.venue}` : ""}. Du hattest es dir gemerkt.` },
        { title: "Jetzt noch Tickets sichern?", body: `Für „${f.title}“ gibt es nur noch Restkarten.` },
      ]);
    case "concert_day":
      return pick(c.dedupe_key, [
        { title: `Heute Abend: ${f.title}`, body: `${f.time} Uhr${f.venue ? `, ${f.venue}` : ""}.${f.doors ? ` ${f.doors}.` : ""} Anreise findest du in der App.` },
        { title: "Heute ist Konzerttag", body: `${name}um ${f.time} Uhr beginnt „${f.title}“.` },
        { title: `${f.time} Uhr${f.venue ? ` · ${f.venue}` : ""}`, body: `„${f.title}“ – viel Freude heute Abend!` },
      ]);
    case "how_was_it":
      return pick(c.dedupe_key, [
        { title: "Wie war's gestern?", body: `Gib „${f.title}“ ein paar Sterne – deine Freunde sehen es.` },
        { title: `Nachklang: ${f.title}`, body: "Wie hat es dir gefallen? Ein Tipp genügt." },
      ]);
    case "weekly_pick":
      return pick(c.dedupe_key, [
        { title: `${name}unser Tipp der Woche`.replace(/^,\s*/, ""), body: `„${f.title}“, ${f.day} ${f.time} Uhr${f.venue ? `, ${f.venue}` : ""}.` },
        { title: f.title, body: `${f.reason ?? "Passt zu dir"} · ${f.day}, ${f.date}` },
      ]);
    case "reengagement":
      return pick(c.dedupe_key, [
        { title: "Lust auf einen Konzertabend?", body: `„${f.title}“ am ${f.date} könnte dir gefallen.` },
        { title: `${name}schon lange nicht mehr im Konzert?`.replace(/^,\s*/, ""), body: `Wie wäre es mit „${f.title}“ – ${f.day}, ${f.date}?` },
      ]);
    default:
      return { title: "Klangradar", body: f.title ?? "Neues für dich" };
  }
}

const TONE: Record<string, string> = {
  new_followed: "freudig-neugierig, wie eine gute Nachricht unter Musikfreunden",
  almost_sold_out: "dringlich, aber nicht reißerisch",
  concert_day: "warm und vorfreudig, praktisch (Uhrzeit, Ort)",
  how_was_it: "persönlich und leicht, wie eine Frage unter Freunden",
  weekly_pick: "empfehlend, mit einem konkreten Detail zum Werk oder zur Besetzung",
  reengagement: "einladend, ohne Vorwurf",
};

export const SYSTEM_PROMPT =
  "Du schreibst Push-Mitteilungen für Klangradar, eine App für Klassik-Konzerte. Deutsch, du-Form. " +
  "Titel höchstens 45 Zeichen, Text höchstens 120 Zeichen. Nutze AUSSCHLIESSLICH die gegebenen Fakten – " +
  "erfinde keine Namen, Zahlen, Uhrzeiten, Preise oder Restkartenzahlen. Kein Marketing-Sprech, keine Ausrufezeichen-Ketten, " +
  "höchstens ein Emoji. Schreibe abwechslungsreich, nicht nach Schema „Neu: …“. Ein konkretes Detail (Werk, Dirigent:in, Ort) macht es lebendig.";

export function userPrompt(c: Candidate): string {
  return `Anlass: ${c.kind}\nTon: ${TONE[c.kind] ?? "freundlich"}\nFakten (JSON): ${JSON.stringify(enrichFacts(c))}`;
}

export const TEXT_FUNCTION = {
  name: "push_text",
  description: "Titel und Text einer Push-Mitteilung.",
  parameters: {
    type: "object",
    properties: {
      title: { type: "string", description: "Titel, höchstens 45 Zeichen" },
      body: { type: "string", description: "Text, höchstens 120 Zeichen" },
    },
    required: ["title", "body"],
  },
};

/** Zahlen im Text müssen in den Fakten vorkommen; keine Links; Längen. */
export function validateText(text: PushText, c: Candidate): boolean {
  const title = text.title?.trim() ?? "";
  const body = text.body?.trim() ?? "";
  if (!title || !body || title.length > 60 || body.length > 160) return false;
  if (/https?:|www\.|\.de\b|\.com\b/i.test(title + body)) return false;
  const factsText = JSON.stringify(enrichFacts(c));
  for (const number of (title + " " + body).match(/\d+/g) ?? []) {
    if (!factsText.includes(number)) return false;
  }
  return true;
}
