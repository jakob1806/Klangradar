"use client";

import Image from "next/image";
import { formatMunichDateTime } from "@/lib/munich-time";

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
    <div className="overflow-hidden rounded-2xl border border-black/[0.06] bg-white">
      <div className="relative aspect-[16/9] bg-[#f5f5f7]">
        {preview.imageUrl ? (
          <Image src={preview.imageUrl} alt="" fill className="object-cover" sizes="320px" unoptimized />
        ) : (
          <div className="flex h-full items-end bg-gradient-to-br from-[#e8efff] to-[#f5f5f7] p-4">
            <span className="text-xs font-medium text-[#48484a]">Klangradar</span>
          </div>
        )}
      </div>
      <div className="p-4">
        <p className="text-xs font-semibold text-[#0071e3]">{start ?? "Datum folgt"}</p>
        <h3 className="mt-1.5 text-base font-semibold leading-tight text-[#1d1d1f]">{preview.title || "Titel deines Events"}</h3>
        {preview.subtitle && <p className="mt-1 text-sm text-[#48484a]">{preview.subtitle}</p>}
        <div className="mt-3 space-y-1 border-t border-black/[0.06] pt-3 text-sm">
          <p className="font-medium text-[#1d1d1f]">{preview.venueName || "Venue wird noch bekanntgegeben"}</p>
          <p className="text-[#48484a]">{price ?? "Preisinformation folgt"}</p>
          {preview.doorsInfo && <p className="text-[#48484a]">{preview.doorsInfo}</p>}
        </div>
      </div>
    </div>
  );
}
