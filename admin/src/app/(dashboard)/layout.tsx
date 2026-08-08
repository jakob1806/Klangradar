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
      <main className="flex-1 min-w-0 bg-white text-neutral-900">
        <div className="hidden justify-end border-b border-neutral-200 bg-white px-8 py-3 md:flex">
          <SignOutButton />
        </div>
        <div className="dashboard-content">{children}</div>
      </main>
    </div>
  );
}
