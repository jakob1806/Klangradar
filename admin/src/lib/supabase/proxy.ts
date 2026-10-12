import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Aktualisiert die Supabase-Session innerhalb von proxy.ts (Next.js 16 —
 * ehemals middleware.ts). Muss auf einer echten NextRequest/NextResponse
 * arbeiten statt auf next/headers' cookies(), da Proxy vor dem Rendering
 * läuft.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // getClaims() statt getUser(): prüft die JWT-Signatur (bei asymmetrischen
  // Schlüsseln lokal, ohne Netzwerkaufruf zum Auth-Server) und frischt die
  // Session-Cookies bei Bedarf auf. getUser() kostete auf JEDEM Request —
  // auch beim Vorladen von Links — einen Roundtrip zu Supabase Auth und war
  // ein Hauptgrund für träge Seitenwechsel. Ein gefälschtes Cookie besteht
  // die Signaturprüfung nicht; Seiten und Actions prüfen weiterhin selbst.
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  const user = claims?.sub ? { id: claims.sub as string } : null;

  return { response, user, supabase };
}
