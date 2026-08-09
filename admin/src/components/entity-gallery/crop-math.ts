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

/** Größter Ausschnitt im gegebenen Seitenverhältnis (Default: 16:9-Galerie-
 * Ausschnitt), der komplett innerhalb des Originalbilds liegt und dessen
 * Mittelpunkt mit dem des Originalbilds übereinstimmt — der Default-
 * Zuschnitt, bevor eine Redakteurin ihn anpasst (entspricht dem bisherigen
 * automatischen BoxFit.cover-Verhalten der App). Für den runden Avatar-
 * Ausschnitt (siehe avatar-crop-actions.ts) wird aspect=1 übergeben — ein
 * Kreis ist rechnerisch einfach die 1:1-Fläche mit rundem Rahmen. */
export function defaultCropRect(
  naturalWidth: number,
  naturalHeight: number,
  aspect: number = GALLERY_CROP_ASPECT,
): CropRect {
  const imageAspect = naturalWidth / naturalHeight;
  if (imageAspect > aspect) {
    // Bild ist relativ breiter als der Ziel-Ausschnitt — links/rechts beschneiden.
    const width = aspect / imageAspect;
    return { x: (1 - width) / 2, y: 0, width, height: 1 };
  }
  // Bild ist relativ höher als der Ziel-Ausschnitt (oder exakt) — oben/unten beschneiden.
  const height = imageAspect / aspect;
  return { x: 0, y: (1 - height) / 2, width: 1, height };
}
