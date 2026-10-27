// Erstellt von Claude Code. Auswahl der Push-Mitteilungen pro Nutzer.
// Regeln (Plan vom 23.10.2026):
//  - Budget: höchstens 1 Empfehlung pro Tag, 3 pro Woche. "Transaktionale"
//    Mitteilungen (Konzerttag) zählen nicht dazu.
//  - Ruhezeit 21–8 Uhr (Europe/Berlin), außer transaktional im Zeitfenster.
//  - Zeitpunkt: Empfehlungen zur bevorzugten Stunde des Nutzers (aus der
//    App-Nutzung, sonst 18 Uhr) ±1 Stunde; Konzerttag 9–12 Uhr,
//    "Wie war's?" 9–11 Uhr.
//  - Lernen: Arten, die ein Nutzer nach ≥ 8 Sendungen zu < 5 % öffnet,
//    entfallen (außer sehr dringend, Priorität ≥ 80).
//  - Pro Lauf höchstens eine Mitteilung je Nutzer (die wichtigste).
//  - Klangradar Plus (facts.instant): neue Konzerte von Gefolgten kommen
//    sofort, 8–21 Uhr, außerhalb des Budgets (Nachtrag 27.10.2026).

export interface Candidate {
  user_id: string;
  kind: string;
  dedupe_key: string;
  event_id: string | null;
  priority: number;
  transactional: boolean;
  // deno-lint-ignore no-explicit-any
  facts: Record<string, any>;
}

export interface UserContext {
  /** Nicht-transaktionale Sendungen der letzten 24 h / 7 Tage. */
  sentLastDay: number;
  sentLastWeek: number;
  preferredHour: number;
  /** kind → { sent, opened } der letzten 60 Tage. */
  engagement: Record<string, { sent: number; opened: number }>;
}

export const DAILY_BUDGET = 1;
export const WEEKLY_BUDGET = 3;

export function berlinHour(now: Date): number {
  const part = new Intl.DateTimeFormat("en-GB", { hour: "2-digit", hourCycle: "h23", timeZone: "Europe/Berlin" })
    .formatToParts(now).find((p) => p.type === "hour")?.value ?? "12";
  return Number(part);
}

function isInstant(c: Candidate): boolean {
  return c.facts?.instant === true;
}

function inWindow(kind: string, hour: number, preferred: number, instant = false): boolean {
  if (instant) return hour >= 8 && hour < 21;
  switch (kind) {
    case "concert_day": return hour >= 9 && hour < 12;
    case "how_was_it": return hour >= 9 && hour < 11;
    default: {
      if (hour < 8 || hour >= 21) return false;
      // Bevorzugte Stunde, in die Ruhezeit verschoben auf 8 bzw. 20 Uhr.
      const target = Math.min(20, Math.max(8, preferred));
      return Math.abs(hour - target) <= 1;
    }
  }
}

function learnedAway(kind: string, priority: number, ctx: UserContext): boolean {
  const stats = ctx.engagement[kind];
  if (!stats || stats.sent < 8 || priority >= 80) return false;
  return stats.opened / stats.sent < 0.05;
}

/** Wählt pro Nutzer höchstens eine Mitteilung. */
export function selectPushes(candidates: Candidate[], contexts: Map<string, UserContext>, now: Date): Candidate[] {
  const hour = berlinHour(now);
  const byUser = new Map<string, Candidate[]>();
  for (const c of candidates) byUser.set(c.user_id, [...(byUser.get(c.user_id) ?? []), c]);

  const chosen: Candidate[] = [];
  for (const [userId, list] of byUser) {
    const ctx = contexts.get(userId) ?? { sentLastDay: 0, sentLastWeek: 0, preferredHour: 18, engagement: {} };
    const eligible = list
      .filter((c) => inWindow(c.kind, hour, ctx.preferredHour, isInstant(c)))
      .filter((c) => c.transactional || isInstant(c) || (ctx.sentLastDay < DAILY_BUDGET && ctx.sentLastWeek < WEEKLY_BUDGET))
      .filter((c) => !learnedAway(c.kind, c.priority, ctx))
      .sort((a, b) => b.priority - a.priority);
    if (eligible[0]) chosen.push(eligible[0]);
  }
  return chosen;
}
