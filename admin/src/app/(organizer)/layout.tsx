import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { SignOutButton } from "@/components/sign-out-button";

// Eigenes, schlankes Chrome statt (dashboard)/layout.tsx — die Redaktions-
// Sidebar/CityFilterSwitcher dort sind auf die interne Redaktion
// zugeschnitten und für Veranstalter-Nutzer irrelevant/verwirrend. Näher an
// (public)/layout.tsx (Logo + Kopfzeile + Footer), aber mit Portal-Navigation
// statt Marketing-CTA — proxy.ts garantiert hier bereits einen eingeloggten
// Nutzer, keine erneute Auth-Prüfung nötig.
const NAV_ITEMS = [
  { href: "/veranstalter", label: "Dashboard" },
  { href: "/veranstalter/events", label: "Meine Events" },
  { href: "/veranstalter/bibliothek", label: "Bibliothek" },
  { href: "/veranstalter/promote", label: "Push & Promote" },
  { href: "/veranstalter/analytics", label: "Analytics" },
  { href: "/veranstalter/claim", label: "Beanspruchen" },
] as const;

export default async function OrganizerLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className="apple-font flex min-h-screen flex-col bg-[#fbfbfd]">
      <header className="sticky top-0 z-10 border-b border-black/5 bg-white/70 backdrop-blur-xl">
        <div className="flex items-center justify-between px-6 py-3.5">
          <Link href="/veranstalter" className="flex items-center gap-2.5">
            <span className="dashboard-brand-mark" aria-hidden="true">
              <Image src="/app-logo.svg" alt="" width={34} height={34} />
            </span>
            <span className="text-[0.95rem] font-semibold tracking-tight text-[#1d1d1f]">
              Klangradar für Veranstalter
            </span>
          </Link>
          <div className="flex items-center gap-4">
            {user?.email && <span className="text-sm text-[#86868b]">{user.email}</span>}
            <SignOutButton />
          </div>
        </div>
        <nav className="flex items-center gap-1 px-6 pb-2">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="rounded-full px-3 py-1.5 text-sm font-medium text-[#48484a] transition hover:bg-black/[0.04] hover:text-[#1d1d1f]"
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </header>

      <main className="flex-1">{children}</main>
    </div>
  );
}
