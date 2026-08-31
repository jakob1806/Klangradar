import * as React from "react";
import { cn } from "@/lib/utils";

// Kompakter horizontaler Fortschritts-Indikator für mehrstufige Abläufe
// (Promotion-Freigabe, Claim-Prüfung) — macht sichtbar, wo ein Vorgang gerade
// steht, statt nur einen einzelnen Status-Badge zu zeigen. `haltedAt` markiert
// den Schritt, an dem ein Vorgang abgelehnt/storniert wurde (roter Punkt statt
// weiterer grauer Punkte danach).
export function Steps({
  steps,
  currentIndex,
  haltedAt,
  className,
}: {
  steps: string[];
  currentIndex: number;
  haltedAt?: number;
  className?: string;
}) {
  return (
    <ol className={cn("flex items-center gap-0", className)}>
      {steps.map((step, index) => {
        const isHalted = haltedAt === index;
        const isDone = haltedAt === undefined && index < currentIndex;
        const isCurrent = haltedAt === undefined && index === currentIndex;
        const isLast = index === steps.length - 1;

        return (
          <li key={step} className="flex items-center">
            <span className="flex flex-col items-center gap-1">
              <span
                className={cn(
                  "flex size-5 items-center justify-center rounded-full text-[10px] font-bold transition-colors",
                  isHalted && "bg-[#BE185D] text-white",
                  isDone && "bg-[#2D2A6E] text-white",
                  isCurrent && "bg-[#ECEBFA] text-[#2D2A6E] ring-2 ring-[#2D2A6E]",
                  !isHalted && !isDone && !isCurrent && "bg-[#EEEEE9] text-[#A1A1AA]"
                )}
                aria-hidden="true"
              >
                {isDone ? "✓" : isHalted ? "✕" : index + 1}
              </span>
              <span
                className={cn(
                  "whitespace-nowrap text-[10.5px] font-medium",
                  isCurrent ? "text-[#2D2A6E]" : isHalted ? "text-[#BE185D]" : isDone ? "text-[#4a4550]" : "text-[#A1A1AA]"
                )}
              >
                {step}
              </span>
            </span>
            {!isLast && (
              <span
                className={cn(
                  "mx-1.5 mb-4 h-[2px] w-6 rounded-full transition-colors",
                  isDone || (haltedAt !== undefined && index < haltedAt) ? "bg-[#2D2A6E]" : "bg-[#EEEEE9]"
                )}
                aria-hidden="true"
              />
            )}
          </li>
        );
      })}
    </ol>
  );
}
