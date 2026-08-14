import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Klassik München — Admin",
  description: "Redaktions-Dashboard für die Klassik-München-Plattform",
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
