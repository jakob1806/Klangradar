import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

// Erstellt von Claude Code. Ein-Klick-Abmeldung ohne Login:
// GET  = Link in der Mail (zeigt Bestätigung),
// POST = List-Unsubscribe-Post (RFC 8058, Mail-Apps melden direkt ab).
const KINDS = new Set(["weekly_digest", "followed_new_event", "event_changes", "reminder_day_before", "all"]);

async function unsubscribe(url: URL): Promise<boolean> {
  const token = url.searchParams.get("token") ?? "";
  const kind = url.searchParams.get("kind") ?? "all";
  if (!/^[0-9a-f-]{36}$/i.test(token) || !KINDS.has(kind)) return false;
  const { data } = await createAdminClient().rpc("email_unsubscribe", { p_token: token, p_kind: kind });
  return data === true;
}

export async function POST(request: Request) {
  const ok = await unsubscribe(new URL(request.url));
  return NextResponse.json({ ok }, { status: ok ? 200 : 400 });
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const ok = await unsubscribe(url);
  const labels: Record<string, string> = {
    weekly_digest: "„Deine Konzertwoche“",
    followed_new_event: "E-Mails zu neuen Terminen von dir Gefolgter",
    event_changes: "E-Mails zu Absagen und Änderungen",
    reminder_day_before: "Erinnerungen am Vortag",
  };
  const what = labels[url.searchParams.get("kind") ?? ""] ?? "alle E-Mail-Benachrichtigungen";
  const body = ok
    ? `<h1>Abgemeldet</h1><p>Du erhältst ${what} nicht mehr. In der App kannst du das jederzeit unter Profil → Einstellungen → Benachrichtigungen wieder einschalten.</p>`
    : `<h1>Link ungültig</h1><p>Der Abmeldelink ist ungültig oder abgelaufen. Du kannst E-Mails in der App unter Profil → Einstellungen → Benachrichtigungen abschalten.</p>`;
  return new NextResponse(
    `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Klangradar</title>
<style>body{font:16px/1.6 -apple-system,Helvetica,Arial,sans-serif;background:#F4F8FB;color:#0B1520;margin:0;padding:64px 24px}main{max-width:440px;margin:auto;background:#fff;border-radius:24px;padding:32px}h1{font-size:24px;margin:0 0 12px}p{color:#4B5563;margin:0}</style></head><body><main>${body}</main></body></html>`,
    { status: ok ? 200 : 400, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}
