import Link from "next/link";

const NAV_ITEMS = [
  { href: "/events", label: "Veranstaltungen" },
  { href: "/event-groups", label: "Event-Gruppen" },
  { href: "/review-queue", label: "Review-Queue" },
  { href: "/data-quality", label: "Datenqualität" },
  { href: "/duplicates", label: "Duplikate-Review" },
  { href: "/duplicates/works", label: "Werk-Duplikate" },
  { href: "/cancellations", label: "Absage-Review" },
  { href: "/entity-candidates", label: "Entity-Kandidaten" },
  { href: "/sources", label: "Datenquellen & Import" },
  { href: "/venues", label: "Venues" },
  { href: "/persons", label: "Personen" },
  { href: "/ensembles", label: "Ensembles" },
  { href: "/festivals", label: "Festivals" },
  { href: "/media", label: "Bilder" },
  { href: "/tags", label: "Tags" },
  { href: "/regions", label: "Regionen" },
  { href: "/users", label: "Benutzer" },
  { href: "/reports", label: "Fehlerberichte" },
];

export function Sidebar({ userEmail }: { userEmail?: string }) {
  return (
    <aside className="w-60 shrink-0 border-r border-neutral-200 bg-white px-4 py-6 flex flex-col gap-6">
      <div>
        <p className="text-sm font-semibold tracking-tight">Klassik München</p>
        <p className="text-xs text-neutral-500">Redaktions-Dashboard</p>
      </div>
      <nav className="flex flex-col gap-0.5">
        {NAV_ITEMS.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            className="rounded-md px-3 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-100 hover:text-neutral-900"
          >
            {item.label}
          </Link>
        ))}
      </nav>
      {userEmail && (
        <p className="mt-auto truncate text-xs text-neutral-400" title={userEmail}>
          {userEmail}
        </p>
      )}
    </aside>
  );
}
