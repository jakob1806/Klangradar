// Gemeinsame Hilfen für Team-Einladungen im Veranstalterportal.

export const INVITE_ROLE_LABEL: Record<string, string> = {
  owner: "Admin / Owner",
  editor: "Redaktion",
  marketing: "Marketing",
  finance: "Finanzen",
};

export const INVITE_ROLE_DESCRIPTION: Record<string, string> = {
  owner: "Voller Zugriff inklusive Team-Verwaltung",
  editor: "Events und Profile pflegen",
  marketing: "Promotionen buchen und auswerten",
  finance: "Abrechnungen und Rechnungen einsehen",
};

export function siteUrl(): string {
  return (process.env.NEXT_PUBLIC_SITE_URL || "https://klangradar.com").replace(/\/$/, "");
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** HTML-Mail im Look des Veranstalterportals (Indigo #2D2A6E, helle
 * Fläche #F5F5F1, runde Buttons). Tabellen-Layout + Inline-Styles, damit es
 * in allen Mailclients gleich aussieht. */
export function teamInvitationEmail(input: {
  entityName: string;
  inviterName: string;
  role: string;
  token: string;
}): { subject: string; html: string; text: string } {
  const link = `${siteUrl()}/einladung/${input.token}`;
  const entity = escapeHtml(input.entityName);
  const inviter = escapeHtml(input.inviterName);
  const role = escapeHtml(INVITE_ROLE_LABEL[input.role] ?? input.role);
  const roleHint = escapeHtml(INVITE_ROLE_DESCRIPTION[input.role] ?? "");
  const subject = `${input.inviterName} lädt dich zu „${input.entityName}“ im Klangradar-Veranstalterportal ein`;

  const html = `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;padding:0;background:#F5F5F1;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F5F1;padding:32px 12px;">
  <tr><td align="center">
    <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="max-width:560px;width:100%;">
      <tr><td style="padding:0 4px 20px 4px;">
        <table role="presentation" cellspacing="0" cellpadding="0"><tr>
          <td style="width:36px;height:36px;background:#2D2A6E;border-radius:10px;text-align:center;color:#ffffff;font:800 20px/36px -apple-system,'Plus Jakarta Sans',Helvetica,Arial,sans-serif;">K</td>
          <td style="padding-left:10px;font:800 17px -apple-system,'Plus Jakarta Sans',Helvetica,Arial,sans-serif;color:#18181B;letter-spacing:-0.2px;">Klangradar<br><span style="font:400 11px -apple-system,Helvetica,Arial,sans-serif;color:#A1A1AA;letter-spacing:0;">Veranstalter-Portal</span></td>
        </tr></table>
      </td></tr>
      <tr><td style="background:#ffffff;border-radius:20px;padding:36px 32px;border:1px solid rgba(24,24,27,0.06);font-family:-apple-system,'Plus Jakarta Sans',Helvetica,Arial,sans-serif;color:#18181B;">
        <div style="font-size:11px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#2D2A6E;">Einladung ins Team</div>
        <h1 style="margin:10px 0 14px 0;font-size:26px;line-height:1.2;font-weight:800;letter-spacing:-0.4px;color:#18181B;">Du wurdest zu „${entity}“ eingeladen</h1>
        <p style="margin:0 0 20px 0;font-size:15px;line-height:1.6;color:#52525B;"><strong style="color:#18181B;">${inviter}</strong> möchte dich als Teammitglied von <strong style="color:#18181B;">${entity}</strong> im Klangradar-Veranstalterportal hinzufügen.</p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F5F5F1;border-radius:14px;margin:0 0 26px 0;"><tr><td style="padding:14px 18px;font-size:14px;line-height:1.5;color:#52525B;">
          <span style="color:#A1A1AA;font-size:11px;font-weight:700;letter-spacing:1px;text-transform:uppercase;">Deine Rolle</span><br>
          <strong style="color:#18181B;font-size:15px;">${role}</strong>${roleHint ? ` · ${roleHint}` : ""}
        </td></tr></table>
        <table role="presentation" cellspacing="0" cellpadding="0"><tr><td style="background:#2D2A6E;border-radius:999px;">
          <a href="${link}" style="display:inline-block;padding:14px 28px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">Einladung ansehen</a>
        </td></tr></table>
        <p style="margin:22px 0 0 0;font-size:13px;line-height:1.6;color:#71717A;">Auf der nächsten Seite kannst du die Einladung annehmen oder ablehnen. Der Link ist 14 Tage gültig.</p>
        <p style="margin:14px 0 0 0;font-size:12px;line-height:1.6;color:#A1A1AA;word-break:break-all;">Funktioniert der Button nicht? Kopiere diesen Link in den Browser:<br>${link}</p>
      </td></tr>
      <tr><td style="padding:18px 8px 0 8px;font:12px/1.6 -apple-system,Helvetica,Arial,sans-serif;color:#A1A1AA;text-align:center;">
        Du erhältst diese E-Mail, weil dich ${inviter} zu Klangradar eingeladen hat. Wenn du die Person nicht kennst, kannst du die Einladung ignorieren oder auf der Einladungsseite ablehnen.
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`;

  const text = `${input.inviterName} lädt dich als „${INVITE_ROLE_LABEL[input.role] ?? input.role}“ zum Team von „${input.entityName}“ im Klangradar-Veranstalterportal ein.\n\nEinladung ansehen (annehmen oder ablehnen, 14 Tage gültig):\n${link}\n`;
  return { subject, html, text };
}
