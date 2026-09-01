import { NextResponse, type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/proxy";

const PUBLIC_PATHS = ["/login", "/auth/callback", "/no-access", "/impressum", "/datenschutz"];
// Erfordert Login, aber NICHT admin/editor-Rolle — Veranstalter-Portal,
// Berechtigung läuft pro Zeile über entity_claims (RLS), nicht über die
// globale user_roles-Gate. Bewusst ein eigenes Array statt in PUBLIC_PATHS
// gemischt: PUBLIC_PATHS bedeutet "kein Login nötig", eine stärkere
// Garantie als "Login nötig, Rolle egal" — Vermischen wäre eine leichte
// Falle für eine spätere versehentliche vollständige Öffnung.
const AUTH_ONLY_PATHS = ["/veranstalter"];

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const { response, user, supabase } = await updateSession(request);

  // "/" braucht einen exakten Vergleich statt startsWith — sonst wäre
  // JEDER Pfad ("/events" etc.) über "/".startsWith("/") mit-öffentlich.
  if (pathname === "/" || PUBLIC_PATHS.some((path) => pathname.startsWith(path))) {
    return response;
  }

  if (!user) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("redirectTo", pathname);
    return NextResponse.redirect(loginUrl);
  }

  // Veranstalter-Portal: jeder eingeloggte Nutzer darf rein, VOR dem
  // user_roles-Check — sonst würde jeder Nicht-Redaktions-Nutzer sofort
  // nach /no-access umgeleitet, bevor er das Portal je zu sehen bekäme.
  if (AUTH_ONLY_PATHS.some((path) => pathname.startsWith(path))) {
    return response;
  }

  const { data: roles } = await supabase
    .from("user_roles")
    .select("role")
    .eq("user_id", user.id);

  const isAuthorized = roles?.some((r) => r.role === "admin" || r.role === "editor");
  if (!isAuthorized) {
    return NextResponse.redirect(new URL("/no-access", request.url));
  }

  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|prototypes(?:/|$)|favicon.ico|.*\\.svg$).*)"],
};
