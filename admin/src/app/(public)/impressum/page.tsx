import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Impressum",
  alternates: { canonical: "/impressum" },
};

export default function ImpressumPage() {
  return (
    <div className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="type-heading text-3xl text-[#1d1d1f]">Impressum</h1>
      <p className="mt-2 mb-10 text-sm text-[#86868b]">Angaben gemäß § 5 DDG</p>

      <p className="whitespace-pre-line text-sm leading-relaxed text-[#3a3a3c]">
        {"Jakob Liess\nGabelsbergerstraße 6\n80333 München\nDeutschland"}
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">Kontakt</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        E-Mail: <a href="mailto:jakob@klangradar.com" className="text-[#0071e3] hover:underline">jakob@klangradar.com</a>
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">Verantwortlich für den Inhalt</h2>
      <p className="whitespace-pre-line text-sm leading-relaxed text-[#3a3a3c]">
        {"Jakob Liess\nGabelsbergerstraße 6\n80333 München\nDeutschland"}
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">Haftung für Inhalte</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Die Inhalte dieser App wurden mit größtmöglicher Sorgfalt erstellt. Für die Richtigkeit,
        Vollständigkeit und Aktualität der Inhalte kann jedoch keine Gewähr übernommen werden.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">Haftung für externe Links</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Diese App enthält gegebenenfalls Links zu externen Websites Dritter, auf deren Inhalte kein
        Einfluss besteht. Für diese fremden Inhalte wird daher keine Gewähr übernommen. Für die Inhalte
        der verlinkten Seiten ist stets der jeweilige Anbieter oder Betreiber verantwortlich.
      </p>

      <h2 className="type-heading mt-10 mb-2 text-lg text-[#1d1d1f]">Urheberrecht</h2>
      <p className="text-sm leading-relaxed text-[#3a3a3c]">
        Die durch den Betreiber dieser App erstellten Inhalte und Werke unterliegen dem deutschen
        Urheberrecht. Inhalte Dritter werden als solche gekennzeichnet. Eine Vervielfältigung,
        Bearbeitung, Verbreitung oder sonstige Verwertung außerhalb der Grenzen des Urheberrechts bedarf
        der Zustimmung des jeweiligen Rechteinhabers.
      </p>
    </div>
  );
}
