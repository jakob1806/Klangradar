"use client";

import { useRef, useState, useTransition } from "react";
import { CroppedImagePreview } from "./cropped-image-preview";
import { GALLERY_CROP_ASPECT, defaultCropRect, type CropRect } from "./crop-math";

const FRAME_WIDTH = 440;

/** Interaktives Zuschneide-Tool: Zoom-Regler + Ziehen zum Verschieben,
 * berechnet daraus einen normalisierten Ausschnitt (Anteile 0..1 des
 * Originalbilds) im gegebenen Seitenverhältnis — dieselbe Zahl, die die App
 * später zum Rendern benutzt (siehe crop-math.ts). Rechts daneben eine
 * Live-Vorschau mit exakt derselben Mathematik wie CroppedNetworkImage in
 * der App, damit die Redakteurin sieht, was sie bekommt, bevor sie
 * speichert.
 *
 * `aspect`/`shape` generalisieren das Tool über den ursprünglichen 16:9-
 * Galerie-Ausschnitt hinaus — der runde Avatar-Fokuspunkt (Personen/
 * Ensembles, siehe avatar-crop-actions.ts) nutzt aspect=1, shape="circle",
 * dieselbe Zieh-/Zoom-Mechanik. `onSave`/`onReset` sind austauschbar statt
 * hart auf saveGalleryImageCrop verdrahtet, damit dieselbe Komponente sowohl
 * Galeriebilder (images-Tabelle) als auch Avatar-Crops (persons/ensembles)
 * speichern kann. */
export function CropTool({
  src,
  initialCrop,
  aspect = GALLERY_CROP_ASPECT,
  shape = "rectangle",
  title = "Querformat-Ausschnitt festlegen",
  onSave,
  onReset,
  onClose,
}: {
  src: string;
  initialCrop: CropRect | null;
  aspect?: number;
  shape?: "rectangle" | "circle";
  title?: string;
  onSave: (crop: CropRect) => Promise<void>;
  onReset: () => Promise<void>;
  onClose: () => void;
}) {
  const FRAME_HEIGHT = FRAME_WIDTH / aspect;
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const dragRef = useRef<{ startX: number; startY: number; offsetX: number; offsetY: number } | null>(null);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  // Sobald die natürlichen Bildmaße bekannt sind (onLoad, nicht als
  // separater Effect — vermeidet einen kaskadierenden Zusatz-Render):
  // Startzustand aus einem vorhandenen Zuschnitt rekonstruieren, sonst den
  // Default-Zuschnitt (zentrierter 16:9-Ausschnitt) als Zoom/Offset
  // ausdrücken.
  function handleImageLoad(e: React.SyntheticEvent<HTMLImageElement>) {
    const w = e.currentTarget.naturalWidth;
    const h = e.currentTarget.naturalHeight;
    const crop = initialCrop ?? defaultCropRect(w, h, aspect);
    const baseScale = Math.max(FRAME_WIDTH / w, FRAME_HEIGHT / h);
    const scale = FRAME_WIDTH / crop.width / w;
    setZoom(Math.max(1, scale / baseScale));
    setOffset({ x: -crop.x * w * scale, y: -crop.y * h * scale });
    setNatural({ w, h });
  }

  if (!natural) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={src} alt="" className="hidden" onLoad={handleImageLoad} />
        <div className="rounded-lg bg-white px-4 py-3 text-sm text-neutral-600">Bild wird geladen…</div>
      </div>
    );
  }

  const baseScale = Math.max(FRAME_WIDTH / natural.w, FRAME_HEIGHT / natural.h);
  const scale = baseScale * zoom;
  const renderedW = natural.w * scale;
  const renderedH = natural.h * scale;

  function clamp(o: { x: number; y: number }) {
    return {
      x: Math.min(0, Math.max(FRAME_WIDTH - renderedW, o.x)),
      y: Math.min(0, Math.max(FRAME_HEIGHT - renderedH, o.y)),
    };
  }

  function currentCrop(): CropRect {
    return {
      x: -offset.x / renderedW,
      y: -offset.y / renderedH,
      width: FRAME_WIDTH / renderedW,
      height: FRAME_HEIGHT / renderedH,
    };
  }

  function handlePointerDown(e: React.PointerEvent) {
    e.currentTarget.setPointerCapture(e.pointerId);
    dragRef.current = { startX: e.clientX, startY: e.clientY, offsetX: offset.x, offsetY: offset.y };
  }

  function handlePointerMove(e: React.PointerEvent) {
    if (!dragRef.current) return;
    const dx = e.clientX - dragRef.current.startX;
    const dy = e.clientY - dragRef.current.startY;
    setOffset(clamp({ x: dragRef.current.offsetX + dx, y: dragRef.current.offsetY + dy }));
  }

  function handlePointerUp() {
    dragRef.current = null;
  }

  function handleZoomChange(next: number) {
    setZoom(next);
    // scaleRatio direkt aus dem Zoom-Verhältnis statt erneut über
    // natural.w/h zu rechnen — vermeidet eine TS-"possibly null"-Warnung
    // durch die Closure und ist ohnehin dieselbe Zahl (renderedW ist schon
    // natural.w * baseScale * zoom).
    const scaleRatio = next / zoom;
    const newRenderedW = renderedW * scaleRatio;
    const newRenderedH = renderedH * scaleRatio;
    // Frame-Mitte als Anker beim Zoomen, nicht die Bildecke — fühlt sich
    // beim Regler-Ziehen sonst wie ein Sprung an.
    const centerX = offset.x + renderedW / 2;
    const centerY = offset.y + renderedH / 2;
    setOffset(
      clamp({
        x: centerX * scaleRatio - newRenderedW / 2,
        y: centerY * scaleRatio - newRenderedH / 2,
      }),
    );
  }

  function handleSave() {
    setError(null);
    const crop = currentCrop();
    startTransition(async () => {
      try {
        await onSave(crop);
        onClose();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Speichern fehlgeschlagen.");
      }
    });
  }

  function handleReset() {
    setError(null);
    startTransition(async () => {
      try {
        await onReset();
        onClose();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Zurücksetzen fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div className="flex max-w-3xl flex-col gap-4 rounded-xl bg-white p-5 shadow-xl">
        <h2 className="text-sm font-semibold text-neutral-900">{title}</h2>

        <div className="flex flex-wrap gap-6">
          <div className="flex flex-col gap-2">
            <span className="text-xs font-medium text-neutral-500">Ausschnitt wählen (ziehen zum Verschieben)</span>
            <div
              className={`relative touch-none select-none overflow-hidden bg-neutral-900 ${shape === "circle" ? "rounded-full" : "rounded-md"}`}
              style={{ width: FRAME_WIDTH, height: FRAME_HEIGHT, cursor: "grab" }}
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={handlePointerUp}
              onPointerLeave={handlePointerUp}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={src}
                alt=""
                draggable={false}
                className="absolute"
                style={{ width: renderedW, height: renderedH, left: offset.x, top: offset.y, maxWidth: "none" }}
              />
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-neutral-500">Zoom</span>
              <input
                type="range"
                min={1}
                max={3}
                step={0.01}
                value={zoom}
                onChange={(e) => handleZoomChange(Number(e.target.value))}
                className="w-40"
              />
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <span className="text-xs font-medium text-neutral-500">So sieht es in der App aus</span>
            <CroppedImagePreview
              src={src}
              crop={currentCrop()}
              aspect={aspect}
              shape={shape}
              className={`w-[220px] ${shape === "circle" ? "" : "rounded-md"}`}
            />
          </div>
        </div>

        {error && <p className="text-xs text-red-600">{error}</p>}

        <div className="flex items-center justify-between">
          <button
            type="button"
            onClick={handleReset}
            disabled={pending}
            className="text-xs font-medium text-neutral-500 hover:text-neutral-800 disabled:opacity-50"
          >
            Auf Standard zurücksetzen
          </button>
          <div className="flex gap-3">
            <button
              type="button"
              onClick={onClose}
              disabled={pending}
              className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50 disabled:opacity-50"
            >
              Abbrechen
            </button>
            <button
              type="button"
              onClick={handleSave}
              disabled={pending}
              className="rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
            >
              {pending ? "Speichere…" : "Speichern"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
