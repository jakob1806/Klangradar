// Erstellt von Claude Code. Auswahl der Push-Mitteilungen pro Nutzer.
// Regeln seit 01.11.2026 (Nutzerentscheidung, docs/14-mitteilungen-konzept.md):
//  - Planung (Konzerttag, transaktional) kommt immer, genau eine pro Konzert
//    (dedupe "concert:<id>"), 9–12 Uhr. Wichtiges (Absagen, direkte
//    Freundes-Anfragen) verschicken notify-changes/notify-social sofort.
//  - Alles andere teilt sich ein Wochenbudget, das jede:r selbst wählt
//    (Standard 10, 3–40). Pro Tag höchstens ein Viertel davon (mind. 2) und
//    mindestens 2 Stunden Abstand zwischen zwei solchen Mitteilungen.
//    Vorher: Plus-"Sofort" außerhalb jedes Budgets -> am 01.11. 52 Pushes
//    an einen Nutzer.
//  - Ruhezeit 21–8 Uhr. Zeitpunkt: bevorzugte Stunde ±1 (sonst 18 Uhr);
//    zweite Plus-Sammlung des Tages ("…a") mittags 11–13 Uhr.
//  - Lernen: Arten, die jemand nach ≥ 8 Sendungen zu < 5 % öffnet, entfallen
//    (außer Priorität ≥ 80).
//  - Pro Lauf höchstens eine Mitteilung je Nutzer (die wichtigste).

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
  /** Zeitpunkt der letzten nicht-transaktionalen Sendung (ms). */
  lastSentAt?: number;
  preferredHour: number;
  /** Selbst gewähltes Wochenbudget (Standard 10). */
  weeklyLimit?: number;
  /** kind → { sent, opened } der letzten 60 Tage. */
  engagement: Record<string, { sent: number; opened: number }>;
}

export const DEFAULT_WEEKLY_LIMIT = 10;
export const MIN_GAP_MS = 2 * 3600 * 1000;

export function dailyLimit(weekly: number): number {
  return Math.max(2, Math.ceil(weekly / 4));
}

export function berlinHour(now: Date): number {
  const part = new Intl.DateTimeFormat("en-GB", { hour: "2-digit", hourCycle: "h23", timeZone: "Europe/Berlin" })
    .formatToParts(now).find((p) => p.type === "hour")?.value ?? "12";
  return Number(part);
}

function inWindow(c: Candidate, hour: number, preferred: number): boolean {
  switch (c.kind) {
    case "concert_day": return hour >= 9 && hour < 12;
    case "how_was_it": return hour >= 9 && hour < 11;
    default: {
      if (hour < 8 || hour >= 21) return false;
      // Erste von zwei Plus-Sammlungen am Tag: mittags.
      if (c.kind === "new_followed" && c.dedupe_key.endsWith("a")) return hour >= 11 && hour < 13;
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

function withinBudget(ctx: UserContext, now: Date): boolean {
  const weekly = ctx.weeklyLimit ?? DEFAULT_WEEKLY_LIMIT;
  if (ctx.sentLastWeek >= weekly || ctx.sentLastDay >= dailyLimit(weekly)) return false;
  return ctx.lastSentAt == null || now.getTime() - ctx.lastSentAt >= MIN_GAP_MS;
}

/** Wählt pro Nutzer höchstens eine Mitteilung. */
export function selectPushes(candidates: Candidate[], contexts: Map<string, UserContext>, now: Date): Candidate[] {
  const hour = berlinHour(now);
  const byUser = new Map<string, Candidate[]>();
  for (const c of candidates) byUser.set(c.user_id, [...(byUser.get(c.user_id) ?? []), c]);

  const chosen: Candidate[] = [];
  for (const [userId, list] of byUser) {
    const ctx = contexts.get(userId) ?? { sentLastDay: 0, sentLastWeek: 0, preferredHour: 18, engagement: {} };
    const budgetOk = withinBudget(ctx, now);
    const eligible = list
      .filter((c) => inWindow(c, hour, ctx.preferredHour))
      .filter((c) => c.transactional || budgetOk)
      .filter((c) => !learnedAway(c.kind, c.priority, ctx))
      .sort((a, b) => b.priority - a.priority);
    if (eligible[0]) chosen.push(eligible[0]);
  }
  return chosen;
}
