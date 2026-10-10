"use client";

import * as React from "react";
import Image from "next/image";
import { Menu } from "lucide-react";
import { Sheet, SheetContent, SheetTrigger, SheetHeader, SheetTitle } from "@/components/organizer/ui/sheet";
import { SidebarNavigation } from "@/components/organizer/sidebar-nav";

export function MobileSidebarTrigger() {
  const [open, setOpen] = React.useState(false);

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger className="flex size-10 items-center justify-center rounded-[10px] text-[#4A4A4A] transition hover:bg-[#111111]/[0.05] hover:text-[#111111] lg:hidden">
        <Menu className="size-5" />
        <span className="sr-only">Navigation öffnen</span>
      </SheetTrigger>
      <SheetContent side="left" className="flex flex-col border-[#111111]/10 bg-white p-0 pt-5">
        <SheetHeader>
          <div className="flex items-center gap-2.5 px-5 pb-4">
            <Image src="/app-logo.svg" alt="Klangradar" width={32} height={32} className="rounded-[9px]" />
            <span className="flex flex-col leading-none">
              <span className="text-[15px] font-extrabold tracking-tight text-[#111111]">Klangradar</span>
              <SheetTitle className="text-[11px] font-normal text-[#8A8A8A]">Veranstalter-Portal</SheetTitle>
            </span>
          </div>
        </SheetHeader>
        <SidebarNavigation onNavigate={() => setOpen(false)} />
      </SheetContent>
    </Sheet>
  );
}
