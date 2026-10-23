// Erstellt von Claude Code. Mails an App-Nutzer (nicht Veranstalter):
// "Deine Konzertwoche" und "Neue Termine von dir Gefolgten".
// Klangradar-App-Design (Blau #146194), Konzertkarten mit Bild, Grund und
// Termin, Abmeldelink + List-Unsubscribe (Ein-Klick-Abmeldung in Mail-Apps).
import { getResend } from "@/lib/resend";
import { escapeHtml } from "@/lib/portal-email";

const FROM = "Klangradar <noreply@klangradar.com>";
const FONT = "-apple-system,'SF Pro Text',Helvetica,Arial,sans-serif";
const ACCENT = "#146194";
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

function eventCard(event: MailEvent): string {
  const image = event.imageUrl
    ? `<td width="96" style="padding:0 14px 0 0;vertical-align:top;"><img src="${escapeHtml(event.imageUrl)}" width="96" height="96" alt="" style="display:block;width:96px;height:96px;border-radius:14px;object-fit:cover;"></td>`
    : "";
  const reason = event.reason
    ? `<div style="margin-top:6px;font-size:12px;font-weight:600;color:${ACCENT};">${escapeHtml(event.reason)}</div>`
    : "";
  return `<tr><td style="padding:0 0 12px 0;">
    <a href="${eventLink(event.slug)}" style="text-decoration:none;color:inherit;display:block;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F2F6FA;border-radius:18px;padding:12px;">
      <tr>${image}<td style="vertical-align:top;font-family:${FONT};">
        <div style="font-size:12px;font-weight:600;color:#6B7280;text-transform:uppercase;letter-spacing:.4px;">${escapeHtml(formatEventDate(event.startDatetime))}</div>
        <div style="margin-top:4px;font-size:16px;line-height:1.3;font-weight:700;color:#0B1520;">${escapeHtml(event.title)}</div>
        ${event.venueName ? `<div style="margin-top:3px;font-size:13px;color:#4B5563;">${escapeHtml(event.venueName)}</div>` : ""}
        ${reason}
      </td></tr>
    </table></a>
  </td></tr>`;
}

export function userEmail(input: {
  subject: string;
  preheader: string;
  eyebrow: string;
  title: string;
  intro: string;
  sections: { heading?: string; events: MailEvent[] }[];
  cta?: { label: string; href: string };
  reasonForEmail: string;
  unsubscribeToken: string;
  unsubscribeKind: "weekly_digest" | "followed_new_event" | "event_changes" | "reminder_day_before";
}): UserEmail {
  const unsubscribeUrl = `${SITE}/api/email/unsubscribe?token=${encodeURIComponent(input.unsubscribeToken)}&kind=${input.unsubscribeKind}`;
  const sections = input.sections
    .filter((section) => section.events.length > 0)
    .map((section) => `${section.heading ? `<h2 style="margin:26px 0 12px 0;font:700 17px ${FONT};color:#0B1520;">${escapeHtml(section.heading)}</h2>` : ""}
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0">${section.events.map(eventCard).join("")}</table>`)
    .join("");
  const cta = input.cta
    ? `<table role="presentation" cellspacing="0" cellpadding="0" style="margin-top:22px;"><tr><td style="background:${ACCENT};border-radius:999px;"><a href="${escapeHtml(input.cta.href)}" style="display:inline-block;padding:14px 26px;font:700 15px ${FONT};color:#ffffff;text-decoration:none;">${escapeHtml(input.cta.label)}</a></td></tr></table>`
    : "";

  const html = `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${escapeHtml(input.subject)}</title></head>
<body style="margin:0;padding:0;background:#E9F1F8;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(input.preheader)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:linear-gradient(180deg,#DCEAF6,#F4F8FB);padding:28px 12px;">
  <tr><td align="center">
    <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="max-width:560px;width:100%;">
      <tr><td style="padding:0 6px 18px 6px;">
        <table role="presentation" cellspacing="0" cellpadding="0"><tr>
          <td style="width:38px;height:38px;background:${ACCENT};border-radius:11px;text-align:center;color:#fff;font:800 21px/38px ${FONT};">K</td>
          <td style="padding-left:10px;font:800 18px ${FONT};color:#0B1520;letter-spacing:-.2px;">Klangradar</td>
        </tr></table>
      </td></tr>
      <tr><td style="background:#ffffff;border-radius:24px;padding:30px 24px;font-family:${FONT};color:#0B1520;box-shadow:0 10px 30px rgba(20,97,148,.08);">
        <div style="font-size:11px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:${ACCENT};">${escapeHtml(input.eyebrow)}</div>
        <h1 style="margin:8px 0 12px 0;font-size:26px;line-height:1.2;font-weight:800;letter-spacing:-.5px;">${escapeHtml(input.title)}</h1>
        <p style="margin:0;font-size:15px;line-height:1.6;color:#4B5563;">${escapeHtml(input.intro)}</p>
        ${sections}${cta}
      </td></tr>
      <tr><td style="padding:18px 10px 0 10px;font:12px/1.6 ${FONT};color:#6B7280;text-align:center;">
        ${escapeHtml(input.reasonForEmail)}<br>
        <a href="${unsubscribeUrl}" style="color:#6B7280;">Abmelden</a> · Einstellungen in der App unter Profil → Einstellungen → Benachrichtigungen<br>
        <a href="${SITE}/impressum" style="color:#6B7280;">Impressum</a> · <a href="${SITE}/datenschutz" style="color:#6B7280;">Datenschutz</a>
      </td></tr>
    </table>
  </td></tr>
</table></body></html>`;

  const text = [
    input.title,
    "",
    input.intro,
    ...input.sections.flatMap((section) => [
      "",
      ...(section.heading ? [section.heading.toUpperCase()] : []),
      ...section.events.map((e) => `• ${formatEventDate(e.startDatetime)} – ${e.title}${e.venueName ? `, ${e.venueName}` : ""}${e.reason ? ` (${e.reason})` : ""}`),
    ]),
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
