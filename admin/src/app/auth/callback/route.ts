import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/** Tauscht den Magic-Link-Code aus der E-Mail gegen eine Session (PKCE-Flow).
 * Das Sprungziel kommt aus dem post_login_redirect-Cookie (von login/page.tsx
 * gesetzt) statt aus der Redirect-URL selbst — die muss exakt mit einer bei
 * Supabase freigegebenen URL übereinstimmen, ein angehängter Query-String
 * hätte den Redirect sonst zum Scheitern gebracht. */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const redirectTo = request.cookies.get("post_login_redirect")?.value ?? "/admin";

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      const response = NextResponse.redirect(`${origin}${redirectTo}`);
      response.cookies.delete("post_login_redirect");
      return response;
    }
  }

  return NextResponse.redirect(`${origin}/login?error=auth`);
}
