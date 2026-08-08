import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseEmailAllowlist, resolvePortalAccess } from "./access.ts";

// Der Link bleibt für normale App-Konten durch das Server-Passwort geschützt.
// Explizit freigegebene Konten dürfen ihn ohne zusätzliche Passwortabfrage
// öffnen. Die Function vertraut dabei nie einer vom Client gesendeten E-Mail:
// sie validiert das echte Supabase-JWT und liest die E-Mail aus dem dadurch
// bestätigten User. Passwort und Allowlist liegen ausschließlich als Secrets
// auf dem Server und damit nicht im auslesbaren App-Bundle.
Deno.serve(async (req) => {
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // Ein leerer Body ist der beabsichtigte Account-Check vor dem Öffnen der
    // Passwortabfrage. Ungültiges JSON gewährt dadurch niemals Zugriff.
  }

  const submitted = typeof body.password === "string" ? body.password : "";
  const expected = Deno.env.get("ADMIN_PORTAL_PASSWORD") ?? "";
  const portalUrl = Deno.env.get("ADMIN_PORTAL_URL") ?? "";
  const passwordlessEmails = parseEmailAllowlist(
    Deno.env.get("ADMIN_PORTAL_PASSWORDLESS_EMAILS") ?? "",
  );
  const authenticatedEmail = await getAuthenticatedEmail(req);
  const accessMode = resolvePortalAccess({
    authenticatedEmail,
    passwordlessEmails,
    submittedPassword: submitted,
    expectedPassword: expected,
  });
  const valid = accessMode !== null;

  return new Response(
    JSON.stringify(
      valid
        ? { valid: true, portalUrl, accessMode }
        : { valid: false, passwordRequired: true },
    ),
    { headers: { "Content-Type": "application/json" } },
  );
});

async function getAuthenticatedEmail(req: Request): Promise<string | null> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return null;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user?.email || data.user.is_anonymous) return null;
  return data.user.email;
}
