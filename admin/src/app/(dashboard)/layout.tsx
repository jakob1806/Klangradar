import Link from "next/link";
import { Sidebar } from "@/components/sidebar";
import { MobileNavigation } from "@/components/mobile-navigation";
import { MobileTableAdapter } from "@/components/mobile-table-adapter";
import { SignOutButton } from "@/components/sign-out-button";
import { CityFilterSwitcher } from "@/components/city-filter-switcher";
import { createClient } from "@/lib/supabase/server";
import { getActiveCityFilter, getCityFilterOptions } from "@/lib/city-filter";

export default async function DashboardLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const supabase = await createClient();
  const [
    {
      data: { user },
    },
    cityOptions,
    activeCity,
  ] = await Promise.all([supabase.auth.getUser(), getCityFilterOptions(), getActiveCityFilter()]);

  return (
    <div className="dashboard-shell flex min-h-full">
      <a href="#dashboard-content" className="skip-link">Zum Hauptinhalt springen</a>
      <MobileTableAdapter />
      <div className="hidden shrink-0 md:flex">
        <Sidebar userEmail={user?.email} />
      </div>
      <div className="mobile-dashboard-header md:hidden">
        <MobileNavigation>
          <Sidebar userEmail={user?.email} />
        </MobileNavigation>
        <SignOutButton />
      </div>
      <main id="dashboard-content" tabIndex={-1} className="dashboard-main min-w-0 flex-1">
        <div className="dashboard-topbar sticky top-0 z-30 hidden items-center justify-between px-8 md:flex">
          <div>
            <p className="text-[13px] font-semibold tracking-tight text-[#1d1d1f]">Klangradar Redaktion</p>
            <p className="text-[11px] text-[#86868b]">Inhalte zentral verwalten</p>
          </div>
          <div className="flex items-center gap-4">
            <Link
              href="/veranstalter"
              className="rounded-full border border-black/10 px-3 py-1.5 text-xs font-semibold text-[#48484a] transition hover:bg-black/[0.04] hover:text-[#1d1d1f]"
            >
              Veranstalterportal
            </Link>
            <CityFilterSwitcher cities={cityOptions} activeSlug={activeCity.slug} />
            <SignOutButton />
          </div>
        </div>
        <div className="dashboard-content">{children}</div>
      </main>
    </div>
  );
}
