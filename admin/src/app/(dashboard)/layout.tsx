import Link from "next/link";
import { Sidebar } from "@/components/sidebar";
import { DashboardBreadcrumb } from "@/components/dashboard-breadcrumb";
import type { Metadata } from "next";
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
      <main className="dashboard-main min-w-0 flex-1">
        <div className="dashboard-topbar sticky top-0 z-30 hidden items-center justify-between gap-6 px-8 md:flex">
          <DashboardBreadcrumb />
          <div className="flex items-center gap-3">
            <Link
              href="/veranstalter"
              className="rounded-lg border border-[#DADADA] bg-white px-3 py-1.5 text-[13px] font-medium text-[#111111] hover:border-[#111111]"
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
export const metadata: Metadata = { robots: { index: false, follow: false } };
