import { NextResponse } from "next/server";

// Universal Links der iOS-App (Associated Domains: applinks:klangradar.com).
// Einladungslinks /f/<CODE> öffnen direkt die App, wenn sie installiert ist. Erstellt von Claude Code.
export const dynamic = "force-static";

export function GET() {
  return NextResponse.json(
    {
      applinks: {
        details: [
          {
            appIDs: ["DVH3MYQ64A.de.klangradar.native"],
            components: [{ "/": "/f/*", comment: "Freundes-Einladung" }],
          },
        ],
      },
    },
    { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" } },
  );
}
