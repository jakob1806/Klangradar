"use client";

import * as React from "react";
import { Menu } from "lucide-react";
import { Sheet, SheetContent, SheetTrigger, SheetHeader, SheetTitle } from "@/components/organizer/ui/sheet";
import { SidebarNavigation } from "@/components/organizer/sidebar-nav";

export function MobileSidebarTrigger() {
  const [open, setOpen] = React.useState(false);

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger className="flex size-10 items-center justify-center rounded-[10px] text-[#4a4550] transition hover:bg-[#18181B]/[0.05] hover:text-[#18181B] lg:hidden">
        <Menu className="size-5" />
        <span className="sr-only">Navigation öffnen</span>
      </SheetTrigger>
      <SheetContent side="left" className="flex flex-col border-[#18181B]/10 bg-white p-0 pt-5">
        <SheetHeader>
          <div className="flex items-center gap-2.5 px-5 pb-4">
            <span className="flex size-8 items-center justify-center rounded-[9px] bg-[#2D2A6E] text-sm font-extrabold text-white">K</span>
            <span className="flex flex-col leading-none">
              <span className="text-[15px] font-extrabold tracking-tight text-[#18181B]">Klangradar</span>
              <SheetTitle className="text-[11px] font-normal text-[#A1A1AA]">Veranstalter-Portal</SheetTitle>
            </span>
          </div>
        </SheetHeader>
        <SidebarNavigation onNavigate={() => setOpen(false)} />
      </SheetContent>
    </Sheet>
  );
}
