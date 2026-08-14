import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Klangradar — Admin",
  description: "Redaktions-Dashboard für Klangradar",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="de" className="h-full antialiased">
      <body className="min-h-full">{children}</body>
    </html>
  );
}
