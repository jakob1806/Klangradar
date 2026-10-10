import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { createClient } from "@/lib/supabase/server";
import { SidebarNavigation } from "@/components/organizer/sidebar-nav";
import { MobileSidebarTrigger } from "@/components/organizer/mobile-sidebar";
import { NotificationBell } from "@/components/organizer/notification-bell";
import { UserMenu } from "@/components/organizer/user-menu";

// Eigenes Chrome statt (dashboard)/layout.tsx — die Redaktions-Sidebar dort
// ist auf interne Redaktion zugeschnitten. Feste, helle Sidebar (Desktop) +
// Sheet (Mobile) aus components/organizer/, bereits vor diesem Layout fertig
// gebaut, aber nie eingebunden — proxy.ts garantiert hier bereits einen
// eingeloggten Nutzer, keine erneute Auth-Prüfung nötig.
export default async function OrganizerLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className="flex min-h-screen bg-white">
      <aside className="fixed inset-y-0 left-0 hidden w-64 flex-col border-r border-[#EAEAEA] bg-white lg:flex">
        <Link href="/veranstalter" className="flex items-center gap-2.5 px-5 py-5">
          <Image src="/app-logo.svg" alt="Klangradar" width={30} height={30} className="rounded-[8px] border border-[#EAEAEA]" />
          <span className="flex flex-col leading-tight">
            <span className="text-[14px] font-semibold tracking-tight text-[#111111]">Klangradar</span>
            <span className="text-[12px] text-[#6B6B6B]">Veranstalter</span>
          </span>
        </Link>
        <SidebarNavigation />
      </aside>

      <div className="flex min-h-screen min-w-0 flex-1 flex-col lg:pl-64">
        <header className="sticky top-0 z-10 flex h-14 items-center justify-between border-b border-[#EAEAEA] bg-white px-5 lg:px-10">
          <div className="flex items-center gap-2 lg:hidden">
            <MobileSidebarTrigger />
            <Image src="/app-logo.svg" alt="" width={26} height={26} className="rounded-[7px]" />
          </div>
          <span className="hidden truncate text-[13px] text-[#6B6B6B] lg:block">{user?.email}</span>
          <div className="flex items-center gap-1">
            <Suspense fallback={<div className="size-9" />}>
              <NotificationBell />
            </Suspense>
            <UserMenu email={user?.email ?? null} />
          </div>
        </header>

        <main className="organizer-content flex-1">{children}</main>
      </div>
    </div>
  );
}
