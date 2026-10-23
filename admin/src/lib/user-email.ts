// Erstellt von Claude Code. Mails an App-Nutzer (nicht Veranstalter):
// "Deine Konzertwoche" und "Neue Termine von dir Gefolgten".
// Klangradar-App-Design (Blau #146194), Konzertkarten mit Bild, Grund und
// Termin, Abmeldelink + List-Unsubscribe (Ein-Klick-Abmeldung in Mail-Apps).
import { getResend } from "@/lib/resend";
import { escapeHtml } from "@/lib/portal-email";

const FROM = "Klangradar <noreply@klangradar.com>";
const FONT = "-apple-system,'SF Pro Text',Helvetica,Arial,sans-serif";
const SITE = process.env.NEXT_PUBLIC_APP_URL ?? "https://klangradar.com";

export type MailEvent = {
  title: string;
  slug: string;
  startDatetime: string;
  venueName: string | null;
  imageUrl: string | null;
  reason?: string | null;
};

export type UserEmail = { subject: string; html: string; text: string; unsubscribeUrl: string };

export function formatEventDate(iso: string): string {
  return new Intl.DateTimeFormat("de-DE", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Europe/Berlin" }).format(new Date(iso));
}

/** https-Link (Universal Link /e/<slug>): öffnet die App, sonst die Konzert-Webseite. */
export function eventLink(slug: string): string {
  return `${SITE}/e/${encodeURIComponent(slug)}`;
}

const INK = "#111111";
const MUTED = "#6B6B6B";
const LINE = "#E6E6E6";
const VIOLET = "#6F7EFA";
const TEAL = "#4FCDBA";
const LOGO = `${SITE}/email/klangradar-logo.png`;

function shortDate(iso: string): { day: string; date: string; time: string } {
  const d = new Date(iso);
  const part = (o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat("de-DE", { ...o, timeZone: "Europe/Berlin" }).format(d);
  return { day: part({ weekday: "short" }).replace(".", ""), date: part({ day: "numeric", month: "numeric" }), time: part({ hour: "2-digit", minute: "2-digit" }) };
}

/** Großes Hauptkonzert oben (erstes Konzert mit Bild). */
function featureBlock(event: MailEvent): string {
  const d = shortDate(event.startDatetime);
  return `<tr><td style="padding:0 0 28px 0;">
    <a href="${eventLink(event.slug)}" style="text-decoration:none;color:${INK};">
      ${event.imageUrl ? `<img src="${escapeHtml(event.imageUrl)}" width="512" height="300" alt="" style="display:block;width:100%;max-width:512px;height:300px;object-fit:cover;border-radius:6px;">` : ""}
      <div style="margin-top:14px;font:600 13px ${FONT};color:${MUTED};">${escapeHtml(`${d.day} ${d.date} · ${d.time} Uhr${event.venueName ? ` · ${event.venueName}` : ""}`)}</div>
      <div style="margin-top:4px;font:700 22px/1.25 ${FONT};color:${INK};letter-spacing:-.3px;">${escapeHtml(event.title)}</div>
      ${event.reason ? `<div style="margin-top:6px;font:14px/1.5 ${FONT};color:${MUTED};">${escapeHtml(event.reason)}</div>` : ""}
    </a>
  </td></tr>`;
}

/** Terminzeile im Stil eines Programmhefts: Datum links, Titel rechts. */
function listRow(event: MailEvent): string {
  const d = shortDate(event.startDatetime);
  return `<tr>
    <td width="64" style="padding:14px 12px 14px 0;border-top:1px solid ${LINE};vertical-align:top;font:600 13px/1.35 ${FONT};color:${INK};">${escapeHtml(d.day)}<br><span style="font-weight:400;color:${MUTED};">${escapeHtml(d.date)}<br>${escapeHtml(d.time)}</span></td>
    <td style="padding:14px 0;border-top:1px solid ${LINE};vertical-align:top;font-family:${FONT};">
      <a href="${eventLink(event.slug)}" style="text-decoration:none;color:${INK};font:600 15px/1.35 ${FONT};">${escapeHtml(event.title)}</a>
      <div style="margin-top:3px;font:13px/1.45 ${FONT};color:${MUTED};">${escapeHtml([event.venueName, event.reason].filter(Boolean).join(" · "))}</div>
    </td>
  </tr>`;
}

export function userEmail(input: {
  subject: string;
  preheader: string;
  /** Kleine Zeile rechts im Kopf, z. B. "KW 43 · München". */
  dateline: string;
  title: string;
  intro: string;
  /** Erstes Konzert groß zeigen. */
  feature?: MailEvent;
  sections: { heading?: string; events: MailEvent[] }[];
  cta?: { label: string; href: string };
  reasonForEmail: string;
  unsubscribeToken: string;
  unsubscribeKind: "weekly_digest" | "followed_new_event" | "event_changes" | "reminder_day_before";
}): UserEmail {
  const unsubscribeUrl = `${SITE}/api/email/unsubscribe?token=${encodeURIComponent(input.unsubscribeToken)}&kind=${input.unsubscribeKind}`;
  const sections = input.sections
    .filter((section) => section.events.length > 0)
    .map((section) => `${section.heading ? `<tr><td colspan="2" style="padding:22px 0 8px 0;font:700 13px ${FONT};color:${INK};">${escapeHtml(section.heading)}</td></tr>` : ""}${section.events.map(listRow).join("")}`)
    .join("");
  const cta = input.cta
    ? `<p style="margin:28px 0 0 0;font:15px ${FONT};"><a href="${escapeHtml(input.cta.href)}" style="color:${INK};font-weight:600;text-decoration:underline;text-decoration-color:${VIOLET};text-underline-offset:3px;">${escapeHtml(input.cta.label)} →</a></p>`
    : "";

  const html = `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light only"><title>${escapeHtml(input.subject)}</title></head>
<body style="margin:0;padding:0;background:#ffffff;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(input.preheader)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#ffffff;">
  <tr><td align="center" style="padding:28px 16px 40px 16px;">
    <table role="presentation" width="512" cellspacing="0" cellpadding="0" style="max-width:512px;width:100%;">
      <tr><td style="padding:0 0 22px 0;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr>
          <td style="vertical-align:middle;"><a href="${SITE}" style="text-decoration:none;"><img src="${LOGO}" width="32" height="32" alt="Klangradar" style="display:inline-block;vertical-align:middle;border-radius:8px;border:1px solid ${LINE};"><span style="display:inline-block;vertical-align:middle;margin-left:10px;font:700 16px ${FONT};color:${INK};">Klangradar</span></a></td>
          <td align="right" style="vertical-align:middle;font:13px ${FONT};color:${MUTED};">${escapeHtml(input.dateline)}</td>
        </tr></table>
      </td></tr>
      <tr><td style="height:3px;line-height:3px;font-size:0;background:${INK};">&nbsp;</td></tr>
      <tr><td style="padding:26px 0 0 0;font-family:${FONT};color:${INK};">
        <h1 style="margin:0 0 10px 0;font:800 28px/1.15 ${FONT};letter-spacing:-.6px;color:${INK};">${escapeHtml(input.title)}</h1>
        <p style="margin:0 0 26px 0;font:16px/1.55 ${FONT};color:#333333;">${escapeHtml(input.intro)}</p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          ${input.feature ? featureBlock(input.feature) : ""}
        </table>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">${sections}</table>
        ${cta}
      </td></tr>
      <tr><td style="padding:40px 0 0 0;">
        <table role="presentation" cellspacing="0" cellpadding="0"><tr>
          <td style="width:18px;height:3px;background:${VIOLET};font-size:0;">&nbsp;</td><td style="width:18px;height:3px;background:${TEAL};font-size:0;">&nbsp;</td>
        </tr></table>
        <p style="margin:14px 0 0 0;font:12px/1.65 ${FONT};color:${MUTED};">
          ${escapeHtml(input.reasonForEmail)}<br>
          <a href="${unsubscribeUrl}" style="color:${MUTED};">Abmelden</a> · Einstellungen in der App unter Profil → Einstellungen → Benachrichtigungen<br>
          <a href="${SITE}/impressum" style="color:${MUTED};">Impressum</a> · <a href="${SITE}/datenschutz" style="color:${MUTED};">Datenschutz</a>
        </p>
      </td></tr>
    </table>
  </td></tr>
</table></body></html>`;

  const all = [...(input.feature ? [input.feature] : []), ...input.sections.flatMap((section) => section.events)];
  const text = [
    input.title,
    "",
    input.intro,
    "",
    ...all.map((e) => `${formatEventDate(e.startDatetime)} – ${e.title}${e.venueName ? `, ${e.venueName}` : ""}${e.reason ? ` (${e.reason})` : ""}\n${eventLink(e.slug)}`),
    "",
    input.reasonForEmail,
    `Abmelden: ${unsubscribeUrl}`,
  ].join("\n");
  return { subject: input.subject, html, text, unsubscribeUrl };
}

/** Versand in Paketen à 100 (Resend-Batch) mit List-Unsubscribe-Headern.
 * Liefert die Indizes der erfolgreich versendeten Nachrichten. */
export async function sendUserEmails(messages: { to: string; email: UserEmail }[]): Promise<number[]> {
  const sent: number[] = [];
  for (let i = 0; i < messages.length; i += 100) {
    const chunk = messages.slice(i, i + 100);
    try {
      await getResend().batch.send(
        chunk.map(({ to, email }) => ({
          from: FROM,
          to: [to],
          subject: email.subject,
          html: email.html,
          text: email.text,
          headers: {
            "List-Unsubscribe": `<${email.unsubscribeUrl}>`,
            "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
          },
        })),
      );
      sent.push(...chunk.map((_, offset) => i + offset));
    } catch (error) {
      console.error("Nutzer-Mails konnten nicht gesendet werden:", error);
    }
  }
  return sent;
}
