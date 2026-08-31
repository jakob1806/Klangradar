import { Cormorant_Garamond, Manrope } from "next/font/google";

// Eigenständige Bildsprache fürs Veranstalterportal, bewusst UNABHÄNGIG vom
// Apple-Systemschrift-Ansatz des internen Redaktions-Dashboards (siehe
// globals.css) — Nutzerwunsch: "richtiges Konzept wie eine echte Website"
// statt Apple-Formularoptik. next/font lädt beide Schriften zur Build-Zeit
// selbst und hostet sie mit — kein <link>-Tag zu Google Fonts zur Laufzeit.
// Nur in diesem Route-Segment importiert, das interne Dashboard bleibt
// unverändert bei -apple-system.
export const displaySerif = Cormorant_Garamond({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  variable: "--font-organizer-display",
  display: "swap",
});

export const bodySans = Manrope({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  variable: "--font-organizer-body",
  display: "swap",
});
