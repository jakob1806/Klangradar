import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Klassische Konzerte entdecken",
  description: "Klassische Konzerte entdecken — in München, Berlin, Hamburg, Wien und Frankfurt.",
  alternates: { canonical: "/" },
  openGraph: {
    title: "Klangradar — Klassische Konzerte entdecken",
    description: "Konzerte, Ensembles und Spielstätten an einem Ort.",
    url: "/",
  },
};

export default function PublicHomePage() {
  return (
    <div className="mx-auto flex max-w-3xl flex-col items-center gap-5 px-6 py-24 text-center sm:py-32">
      <span className="type-label">Klangradar</span>
      <h1 className="type-heading text-4xl text-[#1d1d1f] sm:text-5xl">Klassische Konzerte entdecken.</h1>
      <p className="max-w-xl text-lg text-[#48484a]">
        In München, Berlin, Hamburg, Wien und Frankfurt — alle Konzerte, Ensembles und Spielstätten an
        einem Ort.
      </p>
    </div>
  );
}
