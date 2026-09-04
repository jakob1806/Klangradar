import type { Metadata } from "next";
import "./globals.css";
import { ConsentAnalytics } from "@/components/consent-analytics";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_APP_URL ?? "https://klangradar.com"),
  title: { default: "Klangradar", template: "%s | Klangradar" },
  description: "Redaktions-Dashboard für Klangradar",
  openGraph: {
    type: "website",
    siteName: "Klangradar",
    locale: "de_DE",
    images: [{ url: "/icon.png", width: 512, height: 512, alt: "Klangradar" }],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="de" className="h-full antialiased">
      <body className="min-h-full"><ConsentAnalytics />{children}</body>
    </html>
  );
}
