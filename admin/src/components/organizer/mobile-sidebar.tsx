"use client";

import * as React from "react";
import { Menu } from "lucide-react";
import { displaySerif } from "@/app/(organizer)/fonts";
import { Sheet, SheetContent, SheetTrigger, SheetHeader, SheetTitle } from "@/components/organizer/ui/sheet";
import { SidebarNavigation } from "@/components/organizer/sidebar-nav";

export function MobileSidebarTrigger() {
  const [open, setOpen] = React.useState(false);

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger className="flex size-10 items-center justify-center rounded-[8px] text-[#4a4550] transition hover:bg-[#15131a]/[0.05] hover:text-[#15131a] lg:hidden">
        <Menu className="size-5" />
        <span className="sr-only">Navigation öffnen</span>
      </SheetTrigger>
      <SheetContent side="left" className="flex flex-col border-white/10 bg-[#15131a]/97 p-0 pt-5 backdrop-blur-2xl">
        <SheetHeader>
          <div className="flex items-baseline gap-2 px-5 pb-4">
            <span className={`${displaySerif.className} text-xl font-semibold text-white`}>Klangradar</span>
            <SheetTitle className="text-[11px] font-semibold uppercase tracking-[0.14em] text-white/45">Veranstalter</SheetTitle>
          </div>
        </SheetHeader>
        <SidebarNavigation onNavigate={() => setOpen(false)} />
      </SheetContent>
    </Sheet>
  );
}
