"use client";

import { useState } from "react";
import { GALLERY_CROP_ASPECT, defaultCropRect, type CropRect } from "./crop-math";

/** Rendert ein Bild exakt so zugeschnitten, wie es die App-Detailansicht
 * zeigen wird — "So sieht's in der App aus" für das Crop-Tool, aber auch
 * als generische Vorschau in der Galerie-Liste nutzbar. Gleiche Mathematik
 * wie CroppedNetworkImage in der App (Prozentwerte statt fixer Pixel, damit
 * es unabhängig von der tatsächlichen Containergröße stimmt). */
export function CroppedImagePreview({
  src,
  crop,
  naturalWidth,
  naturalHeight,
  aspect = GALLERY_CROP_ASPECT,
  shape = "rectangle",
  className,
}: {
  src: string;
  crop: CropRect | null;
  naturalWidth?: number;
  naturalHeight?: number;
  aspect?: number;
  shape?: "rectangle" | "circle";
  className?: string;
}) {
  const [failed, setFailed] = useState(false);
  const effectiveCrop =
    crop ?? (naturalWidth && naturalHeight ? defaultCropRect(naturalWidth, naturalHeight, aspect) : null);

  return (
    <div
      className={`relative overflow-hidden bg-neutral-100 ${shape === "circle" ? "rounded-full" : ""} ${className ?? ""}`}
      style={{ aspectRatio: `${aspect}` }}
    >
      {failed ? (
        // Quelle nicht ladbar (z.B. Hotlink-Rate-Limit/abgelaufene Fremd-
        // URL) — sichtbarer Hinweis statt einer leeren Fläche, die wie ein
        // Ladefehler der Seite selbst statt eines kaputten Bildlinks aussieht.
        <div className="flex h-full w-full items-center justify-center px-1 text-center text-[10px] text-neutral-400">
          Bild nicht erreichbar
        </div>
      ) : effectiveCrop ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src}
          alt=""
          onError={() => setFailed(true)}
          className="absolute"
          style={{
            width: `${100 / effectiveCrop.width}%`,
            height: `${100 / effectiveCrop.height}%`,
            left: `${(-effectiveCrop.x / effectiveCrop.width) * 100}%`,
            top: `${(-effectiveCrop.y / effectiveCrop.height) * 100}%`,
            maxWidth: "none",
          }}
        />
      ) : (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt="" onError={() => setFailed(true)} className="h-full w-full object-cover" />
      )}
    </div>
  );
}
