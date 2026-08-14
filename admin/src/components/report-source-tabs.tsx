import Link from "next/link";

const SOURCES = [
  { href: "/content-reports", label: "Flutter" },
  { href: "/content-reports-native", label: "Native" },
  { href: "/reports", label: "Systemfehler" },
  { href: "/code-fix-tasks", label: "Automatische Reparaturen" },
];

export function ReportSourceTabs({ activeHref }: { activeHref: string }) {
  return (
    <nav
      className="mb-5 flex w-fit max-w-full gap-1 overflow-x-auto rounded-xl bg-black/[0.045] p-1"
      aria-label="Herkunft der Meldungen"
    >
        {SOURCES.map((source) => (
          <Link key={source.href} href={source.href} className={`whitespace-nowrap rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${activeHref===source.href ? "bg-white text-neutral-950 shadow-sm" : "text-neutral-500 hover:text-neutral-900"}`}>
            {source.label}
          </Link>
        ))}
    </nav>
  );
}
