import { NextResponse, type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/proxy";

const PUBLIC_PATHS = ["/login", "/auth/callback", "/no-access", "/impressum", "/datenschutz"];

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
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.svg$).*)"],
};
