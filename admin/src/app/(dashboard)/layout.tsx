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
      <main className="flex-1 min-w-0 bg-[#f5f5f7] text-[#1d1d1f]">
        <div className="sticky top-0 z-30 hidden justify-end border-b border-black/[0.06] bg-[#f5f5f7]/80 px-8 py-3 backdrop-blur-xl md:flex">
          <SignOutButton />
        </div>
        <div className="dashboard-content">{children}</div>
      </main>
    </div>
  );
}
