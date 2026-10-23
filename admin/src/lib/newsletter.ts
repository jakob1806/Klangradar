// Erstellt von Claude Code. Versand der Nutzer-Mails:
// - "Deine Konzertwoche" (wöchentlich, email_weekly_digest)
// - "Neue Termine von dir Gefolgten" (täglich, email_followed_new_event)
// Beide nur nach aktivem Einschalten in der App; email_log verhindert
// Doppelversand bei mehrfachem Cron-Lauf.
import { createAdminClient } from "@/lib/supabase/admin";
import { sendUserEmails, userEmail, type MailEvent, type UserEmail } from "@/lib/user-email";

type Recipient = { user_id: string; email: string; display_name: string | null; city_id: string | null; city_name: string | null; unsubscribe_token: string };
type Pick = { event_id: string; slug: string; title: string; start_datetime: string; venue_name: string | null; image_url: string | null; reason: string; reason_detail: string; score: number };
type FollowedNew = { event_id: string; slug: string; title: string; start_datetime: string; venue_name: string | null; image_url: string | null; followed_name: string };

const SECTION_ORDER: [string, string][] = [
  ["saved", "Auf deiner Merkliste"],
  ["followed", "Von dir gefolgt"],
  ["friends", "Deine Freunde gehen hin"],
  ["taste", "Das könnte dir gefallen"],
];

/** ISO-Kalenderwoche als Schlüssel, z. B. "2026-W43". */
export function isoWeekKey(date = new Date()): string {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

function firstName(name: string | null): string | null {
  return name?.trim().split(/\s+/)[0] || null;
}

export function weeklyDigestEmail(recipient: Recipient, picks: Pick[]): UserEmail {
  const toEvent = (p: Pick): MailEvent => ({ title: p.title, slug: p.slug, startDatetime: p.start_datetime, venueName: p.venue_name, imageUrl: p.image_url, reason: p.reason_detail });
  const name = firstName(recipient.display_name);
  const top = picks[0];
  return userEmail({
    subject: top ? `Deine Konzertwoche: ${top.title}${picks.length > 1 ? ` und ${picks.length - 1} weitere` : ""}` : "Deine Konzertwoche",
    preheader: `${picks.length} Konzerte für dich${recipient.city_name ? ` in ${recipient.city_name}` : ""} – ausgewählt nach dem, was du magst.`,
    eyebrow: "Deine Konzertwoche",
    title: name ? `Hallo ${name}, das passt zu dir` : "Das passt diese Woche zu dir",
    intro: `Ausgewählt nach deinen gefolgten Künstler:innen, Ensembles und Orten, deiner Merkliste, deinen Lieblingsgenres und dem, was deine Freunde vorhaben${recipient.city_name ? ` – in ${recipient.city_name}` : ""}.`,
    sections: SECTION_ORDER.map(([reason, heading]) => ({ heading, events: picks.filter((p) => p.reason === reason).map(toEvent) })),
    cta: { label: "Alle Konzerte in der App", href: "https://klangradar.com" },
    reasonForEmail: "Du erhältst diese E-Mail, weil du „Deine Konzertwoche“ in der Klangradar-App eingeschaltet hast.",
    unsubscribeToken: recipient.unsubscribe_token,
    unsubscribeKind: "weekly_digest",
  });
}

export function followedNewEventsEmail(recipient: Recipient, events: FollowedNew[]): UserEmail {
  const names = [...new Set(events.map((e) => e.followed_name))];
  const who = names.length === 1 ? names[0] : names.length === 2 ? `${names[0]} und ${names[1]}` : `${names[0]}, ${names[1]} und weitere`;
  return userEmail({
    subject: events.length === 1 ? `Neuer Termin: ${events[0].title}` : `${events.length} neue Termine von ${who}`,
    preheader: `${who} ${names.length === 1 ? "hat" : "haben"} neue Konzerte angekündigt.`,
    eyebrow: "Neu angekündigt",
    title: `Neues von ${who}`,
    intro: "Gerade neu bei Klangradar – von Künstler:innen, Ensembles und Orten, denen du folgst.",
    sections: [{ events: events.map((e) => ({ title: e.title, slug: e.slug, startDatetime: e.start_datetime, venueName: e.venue_name, imageUrl: e.image_url, reason: `Mit ${e.followed_name}` })) }],
    reasonForEmail: "Du erhältst diese E-Mail, weil du E-Mails zu neuen Terminen von dir Gefolgter eingeschaltet hast.",
    unsubscribeToken: recipient.unsubscribe_token,
    unsubscribeKind: "followed_new_event",
  });
}

async function alreadySent(userIds: string[], kind: string, periodKey: string): Promise<Set<string>> {
  if (!userIds.length) return new Set();
  const { data } = await createAdminClient().from("email_log").select("user_id").eq("kind", kind).eq("period_key", periodKey).in("user_id", userIds);
  return new Set((data ?? []).map((row) => row.user_id as string));
}

type Kind = "weekly_digest" | "followed_new_event" | "event_changes" | "reminder_day_before";

async function run<T>(kind: Kind, periodKey: string, load: (r: Recipient) => Promise<T[]>, minItems: number, build: (r: Recipient, items: T[]) => UserEmail) {
  const db = createAdminClient();
  const { data: recipients } = await db.rpc("email_recipients", { p_kind: kind });
  const list = (recipients ?? []) as Recipient[];
  const done = await alreadySent(list.map((r) => r.user_id), kind, periodKey);
  const messages: { to: string; email: UserEmail; userId: string }[] = [];
  for (const recipient of list) {
    if (done.has(recipient.user_id)) continue;
    const items = await load(recipient);
    if (items.length < minItems) continue;
    messages.push({ to: recipient.email, email: build(recipient, items), userId: recipient.user_id });
  }
  const sentIndices = await sendUserEmails(messages);
  if (sentIndices.length > 0) {
    await db.from("email_log").upsert(sentIndices.map((i) => ({ user_id: messages[i].userId, kind, period_key: periodKey })), { ignoreDuplicates: true });
  }
  return { recipients: list.length, sent: sentIndices.length };
}

export async function sendWeeklyDigests() {
  const db = createAdminClient();
  return run<Pick>("weekly_digest", isoWeekKey(), async (r) => {
    const { data } = await db.rpc("newsletter_personal_picks", { p_user: r.user_id, p_days: 10, p_limit: 8 });
    return (data ?? []) as Pick[];
  }, 2, weeklyDigestEmail);
}

export async function sendFollowedNewEventEmails() {
  const db = createAdminClient();
  return run<FollowedNew>("followed_new_event", new Date().toISOString().slice(0, 10), async (r) => {
    const { data } = await db.rpc("followed_new_events_for", { p_user: r.user_id, p_hours: 24 });
    return (data ?? []) as FollowedNew[];
  }, 1, followedNewEventsEmail);
}

type SavedEvent = { event_id: string; slug: string; title: string; start_datetime: string; venue_name: string | null; image_url: string | null; detail: string };
const toMail = (e: SavedEvent): MailEvent => ({ title: e.title, slug: e.slug, startDatetime: e.start_datetime, venueName: e.venue_name, imageUrl: e.image_url, reason: e.detail });

export function reminderEmail(recipient: Recipient, events: SavedEvent[]): UserEmail {
  return userEmail({
    subject: events.length === 1 ? `Morgen: ${events[0].title}` : `Morgen: ${events.length} deiner Konzerte`,
    preheader: "Deine Konzerte für morgen auf einen Blick.",
    eyebrow: "Morgen",
    title: events.length === 1 ? "Morgen ist Konzertabend" : "Morgen hast du Konzerte vor",
    intro: "Kleine Erinnerung an deine gemerkten Konzerte. In der App findest du Anreise, Zeitplan und Restaurants in der Nähe.",
    sections: [{ events: events.map(toMail) }],
    reasonForEmail: "Du erhältst diese E-Mail, weil du E-Mail-Erinnerungen am Vortag eingeschaltet hast.",
    unsubscribeToken: recipient.unsubscribe_token,
    unsubscribeKind: "reminder_day_before",
  });
}

export function changesEmail(recipient: Recipient, events: SavedEvent[]): UserEmail {
  return userEmail({
    subject: events.length === 1 ? `${events[0].detail}: ${events[0].title}` : `${events.length} deiner Konzerte haben sich geändert`,
    preheader: "Änderungen bei deinen gemerkten Konzerten.",
    eyebrow: "Wichtige Änderung",
    title: events.length === 1 ? `${events[0].title} wurde ${events[0].detail === "Abgesagt" ? "abgesagt" : "verschoben"}` : "Änderungen bei deinen Konzerten",
    intro: "Der Veranstalter hat Änderungen gemeldet. Details und gegebenenfalls Hinweise zur Erstattung findest du beim Veranstalter.",
    sections: [{ events: events.map(toMail) }],
    reasonForEmail: "Du erhältst diese E-Mail, weil du E-Mails zu Absagen und Änderungen gemerkter Konzerte eingeschaltet hast.",
    unsubscribeToken: recipient.unsubscribe_token,
    unsubscribeKind: "event_changes",
  });
}

export async function sendReminderEmails() {
  const db = createAdminClient();
  return run<SavedEvent>("reminder_day_before", new Date().toISOString().slice(0, 10), async (r) => {
    const { data } = await db.rpc("saved_events_tomorrow", { p_user: r.user_id });
    return (data ?? []) as SavedEvent[];
  }, 1, reminderEmail);
}

export async function sendChangeEmails() {
  const db = createAdminClient();
  // Pro Tag höchstens eine Änderungs-Mail je Nutzer.
  return run<SavedEvent>("event_changes", new Date().toISOString().slice(0, 10), async (r) => {
    const { data } = await db.rpc("saved_events_changed", { p_user: r.user_id });
    return (data ?? []) as SavedEvent[];
  }, 1, changesEmail);
}
