import * as React from "react";
import { displaySerif } from "@/app/(organizer)/fonts";
import { cn } from "@/lib/utils";

// Gemeinsame redaktionelle Kopfzeile für jede Portal-Seite — großer Serif-
// Titel + Beschreibung + optionale Aktionen rechts, damit sich jede Seite
// wie ein Abschnitt EINER echten Website anfühlt statt wie eine isolierte
// Formularseite (Nutzerwunsch: "richtiges Konzept wie eine echte Website").
export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  className,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  actions?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex flex-col gap-4 border-b border-[#15131a]/[0.07] px-6 py-8 sm:flex-row sm:items-end sm:justify-between lg:px-10", className)}>
      <div className="flex flex-col gap-1.5">
        {eyebrow && <span className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#7d1a3a]">{eyebrow}</span>}
        <h1 className={`${displaySerif.className} text-[2rem] font-semibold leading-tight tracking-tight text-[#15131a] sm:text-[2.35rem]`}>
          {title}
        </h1>
        {description && <p className="max-w-2xl text-[15px] text-[#726c78]">{description}</p>}
      </div>
      {actions && <div className="flex shrink-0 items-center gap-2">{actions}</div>}
    </div>
  );
}

export function PageBody({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("px-6 py-8 lg:px-10", className)} {...props} />;
}
