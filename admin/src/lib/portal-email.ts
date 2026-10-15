import { getResend } from "@/lib/resend";
import { createAdminClient } from "@/lib/supabase/admin";
import { siteUrl } from "@/lib/team-invitation";

// Gemeinsames Mail-Layout im Look des Veranstalterportals (Indigo #2D2A6E,
// helle Fläche #F5F5F1, runde Buttons). Tabellen + Inline-Styles, damit es
// in allen Mailclients gleich aussieht. Inhalte werden escaped.

const FROM = "Klangradar <noreply@klangradar.com>";
const FONT = "-apple-system,'Plus Jakarta Sans',Helvetica,Arial,sans-serif";

export function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export type PortalEmail = { subject: string; html: string; text: string };

export function portalEmail(input: {
  subject: string;
  eyebrow: string;
  title: string;
  paragraphs: string[];
  facts?: [string, string][];
  cta?: { label: string; href: string };
  note?: string;
  footer?: string;
  /** Optionale Tabelle (erste Zeile = Kopf). */
  table?: string[][];
}): PortalEmail {
  const href = input.cta ? (input.cta.href.startsWith("http") ? input.cta.href : `${siteUrl()}${input.cta.href}`) : null;
  const paragraphs = input.paragraphs
    .map((p) => `<p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#52525B;">${escapeHtml(p)}</p>`)
    .join("");
  const facts = input.facts?.length
    ? `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F5F1;border-radius:14px;margin:4px 0 24px 0;">${input.facts
        .map(([label, value]) => `<tr><td style="padding:10px 18px;font-size:14px;line-height:1.5;"><span style="display:block;color:#A1A1AA;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;">${escapeHtml(label)}</span><strong style="color:#18181B;font-size:15px;">${escapeHtml(value)}</strong></td></tr>`)
        .join("")}</table>`
    : "";
  const button = href
    ? `<table role="presentation" cellspacing="0" cellpadding="0"><tr><td style="background:#2D2A6E;border-radius:999px;"><a href="${href}" style="display:inline-block;padding:14px 28px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">${escapeHtml(input.cta!.label)}</a></td></tr></table>`
    : "";
  const table = input.table?.length
    ? `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;margin:4px 0 24px 0;font-size:13px;">${input.table
        .map((row, r) => `<tr>${row.map((cell, c) => `<td style="padding:7px 8px;border-bottom:1px solid #EEEEE9;${c > 0 ? "text-align:right;" : ""}${r === 0 ? "color:#A1A1AA;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;" : "color:#18181B;"}">${escapeHtml(cell)}</td>`).join("")}</tr>`)
        .join("")}</table>`
    : "";
  const note = input.note ? `<p style="margin:22px 0 0 0;font-size:13px;line-height:1.6;color:#71717A;">${escapeHtml(input.note)}</p>` : "";

  const html = `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(input.subject)}</title></head><body style="margin:0;padding:0;background:#F5F5F1;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F5F1;padding:32px 12px;">
  <tr><td align="center">
    <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="max-width:560px;width:100%;">
      <tr><td style="padding:0 4px 20px 4px;">
        <table role="presentation" cellspacing="0" cellpadding="0"><tr>
          <td style="width:36px;height:36px;background:#2D2A6E;border-radius:10px;text-align:center;color:#ffffff;font:800 20px/36px ${FONT};">K</td>
          <td style="padding-left:10px;font:800 17px ${FONT};color:#18181B;letter-spacing:-0.2px;">Klangradar<br><span style="font:400 11px ${FONT};color:#A1A1AA;letter-spacing:0;">Veranstalter-Portal</span></td>
        </tr></table>
      </td></tr>
      <tr><td style="background:#ffffff;border-radius:20px;padding:36px 32px;border:1px solid rgba(24,24,27,0.06);font-family:${FONT};color:#18181B;">
        <div style="font-size:11px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#2D2A6E;">${escapeHtml(input.eyebrow)}</div>
        <h1 style="margin:10px 0 16px 0;font-size:24px;line-height:1.25;font-weight:800;letter-spacing:-0.4px;color:#18181B;">${escapeHtml(input.title)}</h1>
        ${paragraphs}${facts}${table}${button}${note}
        ${href ? `<p style="margin:14px 0 0 0;font-size:12px;line-height:1.6;color:#A1A1AA;word-break:break-all;">Funktioniert der Button nicht? Link: ${href}</p>` : ""}
      </td></tr>
      <tr><td style="padding:18px 8px 0 8px;font:12px/1.6 ${FONT};color:#A1A1AA;text-align:center;">
        ${escapeHtml(input.footer ?? "Du erhältst diese E-Mail, weil du das Klangradar-Veranstalterportal nutzt.")}
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`;

  const text = [
    input.title,
    "",
    ...input.paragraphs,
    ...(input.facts ?? []).map(([label, value]) => `${label}: ${value}`),
    ...(href ? ["", `${input.cta!.label}: ${href}`] : []),
    ...(input.note ? ["", input.note] : []),
  ].join("\n");
  return { subject: input.subject, html, text };
}

/** Versendet eine Portal-Mail. Fehler werden geloggt, nie geworfen: eine
 * fehlgeschlagene Benachrichtigung darf die eigentliche Aktion nicht kippen. */
export async function sendPortalEmail(to: string | string[] | null | undefined, email: PortalEmail): Promise<void> {
  const recipients = (Array.isArray(to) ? to : [to]).filter((value): value is string => Boolean(value));
  if (recipients.length === 0) return;
  try {
    await getResend().emails.send({ from: FROM, to: recipients, subject: email.subject, html: email.html, text: email.text });
  } catch (error) {
    console.error("Portal-Mail konnte nicht gesendet werden:", email.subject, error);
  }
}

export function redaktionEmail(): string {
  return process.env.REDAKTION_EMAIL || "redaktion@klangradar.com";
}

/** E-Mail-Adresse eines Accounts (Service-Client, nur serverseitig). */
export async function accountEmail(userId: string | null | undefined): Promise<string | null> {
  if (!userId) return null;
  try {
    const { data } = await createAdminClient().auth.admin.getUserById(userId);
    return data.user?.email ?? null;
  } catch {
    return null;
  }
}

export function formatConcertDay(iso: string | null | undefined): string {
  if (!iso) return "zum Konzerttag";
  return new Intl.DateTimeFormat("de-DE", { timeZone: "Europe/Berlin", weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(new Date(iso));
}

export const PLACEMENT_NAME: Record<string, string> = {
  standard: "Standard-Platzierung",
  featured: "Featured",
  local_spotlight: "Local Spotlight",
  homepage_feature: "Homepage-Feature",
  push: "Push-Benachrichtigung",
};

export const ENTITY_TYPE_NAME: Record<string, string> = {
  organizer: "Institution",
  person: "Person",
  ensemble: "Ensemble",
  venue: "Spielstätte",
};
