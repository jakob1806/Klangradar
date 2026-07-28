"use client";

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
  className,
}: {
  src: string;
  crop: CropRect | null;
  naturalWidth?: number;
  naturalHeight?: number;
  className?: string;
}) {
  const effectiveCrop =
    crop ?? (naturalWidth && naturalHeight ? defaultCropRect(naturalWidth, naturalHeight) : null);

  return (
    <div
      className={`relative overflow-hidden bg-neutral-100 ${className ?? ""}`}
      style={{ aspectRatio: `${GALLERY_CROP_ASPECT}` }}
    >
      {effectiveCrop ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src}
          alt=""
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
        <img src={src} alt="" className="h-full w-full object-cover" />
      )}
    </div>
  );
}
