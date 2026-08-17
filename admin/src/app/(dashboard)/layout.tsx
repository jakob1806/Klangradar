import { Sidebar } from "@/components/sidebar";
import { MobileNavigation } from "@/components/mobile-navigation";
import { MobileTableAdapter } from "@/components/mobile-table-adapter";
import { SignOutButton } from "@/components/sign-out-button";
import { createClient } from "@/lib/supabase/server";

export default async function DashboardLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

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
        <div className="dashboard-topbar sticky top-0 z-30 hidden items-center justify-between px-8 md:flex">
          <div>
            <p className="text-[13px] font-semibold tracking-tight text-[#1d1d1f]">Klangradar Redaktion</p>
            <p className="text-[11px] text-[#86868b]">Inhalte zentral verwalten</p>
          </div>
          <SignOutButton />
        </div>
        <div className="dashboard-content">{children}</div>
      </main>
    </div>
  );
}
