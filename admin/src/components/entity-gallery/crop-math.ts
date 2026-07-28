/** Gemeinsame Zuschnitt-Mathematik für das Crop-Tool UND die Live-Vorschau
 * (siehe crop-preview.tsx) — beide müssen exakt dasselbe berechnen wie die
 * App (app/lib/core/widgets/cropped_network_image.dart), sonst zeigt die
 * "So sieht's in der App aus"-Vorschau etwas anderes als real angezeigt
 * wird. crop_x/y/width/height sind Anteile (0..1) des Originalbilds. */

export const GALLERY_CROP_ASPECT = 16 / 9;

export interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Größter 16:9-Ausschnitt, der komplett innerhalb des Originalbilds liegt
 * und dessen Mittelpunkt mit dem des Originalbilds übereinstimmt — der
 * Default-Zuschnitt, bevor eine Redakteurin ihn anpasst (entspricht dem
 * bisherigen automatischen BoxFit.cover-Verhalten der App). */
export function defaultCropRect(naturalWidth: number, naturalHeight: number): CropRect {
  const imageAspect = naturalWidth / naturalHeight;
  if (imageAspect > GALLERY_CROP_ASPECT) {
    // Bild ist relativ breiter als 16:9 — links/rechts beschneiden.
    const width = GALLERY_CROP_ASPECT / imageAspect;
    return { x: (1 - width) / 2, y: 0, width, height: 1 };
  }
  // Bild ist relativ höher als 16:9 (oder exakt) — oben/unten beschneiden.
  const height = imageAspect / GALLERY_CROP_ASPECT;
  return { x: 0, y: (1 - height) / 2, width: 1, height };
}
