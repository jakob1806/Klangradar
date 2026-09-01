"use client";

import Image from "next/image";
import { formatMunichDateTime } from "@/lib/munich-time";
import { Card } from "@/components/organizer/ui/card";

export interface EventPreviewData {
  title: string;
  subtitle: string;
  startDatetime: string;
  venueName: string;
  doorsInfo: string;
  isFree: boolean;
  priceMin: string;
  priceMax: string;
  imageUrl: string | null;
}

function priceLabel(preview: EventPreviewData) {
  if (preview.isFree) return "Eintritt frei";
  const min = preview.priceMin ? Number(preview.priceMin) : null;
  const max = preview.priceMax ? Number(preview.priceMax) : null;
  if (min === null && max === null) return null;
  const format = (price: number) => new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(price);
  return min !== null && max !== null && min !== max ? `${format(min)} – ${format(max)}` : format(min ?? max!);
}

// Bewusst dieselbe Optik wie die App-/Website-Detailansicht
// (events/discover/[id]/page.tsx), nur kompakter — Veranstalter sollen
// beim Ausfüllen sehen, wie ihr Event später wirklich aussieht, statt sich
// das aus den Formularfeldern zusammenreimen zu müssen.
export function EventPreviewCard({ preview }: { preview: EventPreviewData }) {
  const price = priceLabel(preview);
  const start = (() => {
    try {
      return preview.startDatetime ? formatMunichDateTime(preview.startDatetime) : null;
    } catch {
      return null;
    }
  })();

  return (
    <Card className="overflow-hidden">
      <div className="relative aspect-[16/9] bg-[#15131a]/[0.04]">
        {preview.imageUrl ? (
          <Image src={preview.imageUrl} alt="" fill className="object-cover" sizes="320px" unoptimized />
        ) : (
          <div className="flex h-full items-end bg-gradient-to-br from-[#2D2A6E]/10 to-[#15131a]/[0.04] p-4">
            <span className="text-xs font-medium text-[#4a4550]">Klangradar</span>
          </div>
        )}
      </div>
      <div className="p-4">
        <p className="text-xs font-semibold text-[#2D2A6E]">{start ?? "Datum folgt"}</p>
        <h3 className="mt-1.5 text-base font-semibold leading-tight text-[#15131a]">{preview.title || "Titel deines Events"}</h3>
        {preview.subtitle && <p className="mt-1 text-sm text-[#4a4550]">{preview.subtitle}</p>}
        <div className="mt-3 space-y-1 border-t border-[#15131a]/[0.08] pt-3 text-sm">
          <p className="font-medium text-[#15131a]">{preview.venueName || "Venue wird noch bekanntgegeben"}</p>
          <p className="text-[#4a4550]">{price ?? "Preisinformation folgt"}</p>
          {preview.doorsInfo && <p className="text-[#4a4550]">{preview.doorsInfo}</p>}
        </div>
      </div>
    </Card>
  );
}
