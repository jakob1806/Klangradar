import Link from "next/link";

const SOURCES = [
  { href: "/content-reports", label: "Flutter" },
  { href: "/content-reports-native", label: "Native" },
  { href: "/reports", label: "Systemfehler" },
  { href: "/code-fix-tasks", label: "Automatische Reparaturen" },
];

export function ReportSourceTabs({ activeHref }: { activeHref: string }) {
  return (
    <div className="mb-6 rounded-2xl border border-black/[0.06] bg-white p-2 shadow-sm">
      <p className="px-2 pb-2 text-xs font-semibold uppercase tracking-[0.14em] text-neutral-400">Meldungen &amp; Fehler</p>
      <nav className="grid grid-cols-2 gap-1 lg:grid-cols-4" aria-label="Herkunft der Meldungen">
        {SOURCES.map((source) => (
          <Link key={source.href} href={source.href} className={`rounded-xl px-3 py-2 text-center text-sm font-medium transition-colors ${activeHref===source.href ? "bg-[#0071e3] text-white" : "text-neutral-600 hover:bg-neutral-100"}`}>
            {source.label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
