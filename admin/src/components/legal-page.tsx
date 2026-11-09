// Gemeinsame Darstellung der Rechtstexte (Quelle: docs/legal/legal_texts.py).
import { LEGAL_STAND } from "@/lib/legal-texts";

export function LegalPage({ title, sections }: { title: string; sections: { title: string; body: string }[] }) {
  return (
    <div className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="type-heading text-3xl text-[#1d1d1f]">{title}</h1>
      <p className="mt-2 mb-10 text-sm text-[#86868b]">Stand: {LEGAL_STAND}</p>
      {sections.map((section) => (
        <section key={section.title} className="mt-10">
          <h2 className="type-heading mb-2 text-lg text-[#1d1d1f]">{section.title}</h2>
          <p className="whitespace-pre-line text-sm leading-relaxed text-[#3a3a3c]">{section.body}</p>
        </section>
      ))}
    </div>
  );
}
