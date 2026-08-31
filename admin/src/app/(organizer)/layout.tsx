import Image from "next/image";
import Link from "next/link";
import { Suspense } from "react";
import { createClient } from "@/lib/supabase/server";
import { SidebarNavigation } from "@/components/organizer/sidebar-nav";
import { MobileSidebarTrigger } from "@/components/organizer/mobile-sidebar";
import { NotificationBell } from "@/components/organizer/notification-bell";
import { UserMenu } from "@/components/organizer/user-menu";
import { bodySans } from "./fonts";

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
    <div className={`${bodySans.variable} flex min-h-screen bg-[#F5F5F1] font-[family-name:var(--font-organizer-body)]`}>
      <aside className="fixed inset-y-0 left-0 hidden w-64 flex-col border-r border-[#18181B]/[0.06] bg-white lg:flex">
        <Link href="/veranstalter" className="flex items-center gap-2.5 px-5 py-6">
          <span className="flex size-8 items-center justify-center rounded-[9px] bg-[#2D2A6E] text-sm font-extrabold text-white">K</span>
          <span className="flex flex-col leading-none">
            <span className="text-[15px] font-extrabold tracking-tight text-[#18181B]">Klangradar</span>
            <span className="text-[11px] text-[#A1A1AA]">Veranstalter-Portal</span>
          </span>
        </Link>
        <SidebarNavigation />
      </aside>

      <div className="flex min-h-screen flex-1 flex-col lg:pl-64">
        <header className="sticky top-0 z-10 flex items-center justify-between border-b border-[#18181B]/[0.06] bg-[#F5F5F1]/90 px-5 py-3 backdrop-blur-xl lg:px-10">
          <div className="flex items-center gap-2 lg:hidden">
            <MobileSidebarTrigger />
            <Image src="/app-logo.svg" alt="" width={26} height={26} />
          </div>
          <span className="hidden text-sm text-[#71717A] lg:block">{user?.email}</span>
          <div className="flex items-center gap-1">
            <Suspense fallback={<div className="size-9" />}>
              <NotificationBell />
            </Suspense>
            <UserMenu email={user?.email ?? null} />
          </div>
        </header>

        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}
