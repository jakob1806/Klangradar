import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { SignOutButton } from "@/components/sign-out-button";
import { OrganizerNavigation } from "./organizer-navigation";

// Eigenes, schlankes Chrome statt (dashboard)/layout.tsx — die Redaktions-
// Sidebar/CityFilterSwitcher dort sind auf die interne Redaktion
// zugeschnitten und für Veranstalter-Nutzer irrelevant/verwirrend. Näher an
// (public)/layout.tsx (Logo + Kopfzeile + Footer), aber mit Portal-Navigation
// statt Marketing-CTA — proxy.ts garantiert hier bereits einen eingeloggten
// Nutzer, keine erneute Auth-Prüfung nötig.
export default async function OrganizerLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className="apple-font flex min-h-screen flex-col bg-[#f7f5f0]">
      <a href="#portal-content" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded-lg focus:bg-white focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:text-[#8b2635] focus:shadow-xl">
        Zum Inhalt springen
      </a>
      <header className="sticky top-0 z-20 border-b border-black/[0.055] bg-[#faf9f6]/90 shadow-[0_1px_0_rgba(255,255,255,0.75)_inset] backdrop-blur-2xl">
        <div className="flex items-center justify-between gap-5 px-5 py-3 sm:px-7">
          <Link href="/veranstalter" className="flex min-w-0 items-center gap-2.5 rounded-lg focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#8b2635]">
            <span className="dashboard-brand-mark" aria-hidden="true">
              <Image src="/app-logo.svg" alt="" width={34} height={34} />
            </span>
            <span className="min-w-0">
              <span className="block truncate text-[0.95rem] font-semibold tracking-[-0.02em] text-[#1d1d1f]">Klangradar Pro</span>
              <span className="block truncate text-[0.67rem] font-medium text-[#77736d]">für Veranstalter</span>
            </span>
          </Link>
          <div className="flex min-w-0 items-center gap-3">
            {user?.email && <span className="hidden max-w-56 truncate text-xs text-[#77736d] sm:block">{user.email}</span>}
            <SignOutButton />
          </div>
        </div>
        <OrganizerNavigation />
      </header>

      <main id="portal-content" className="flex-1">{children}</main>
      <footer className="border-t border-black/[0.06] px-6 py-7 text-xs text-[#77736d]">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3">
          <span>© {new Date().getFullYear()} Klangradar Pro</span>
          <span className="flex gap-4"><Link href="/datenschutz" className="hover:text-[#1d1d1f]">Datenschutz</Link><Link href="/impressum" className="hover:text-[#1d1d1f]">Impressum</Link></span>
        </div>
      </footer>
    </div>
  );
}
