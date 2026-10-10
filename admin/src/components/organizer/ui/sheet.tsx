"use client";

import * as React from "react";
import * as DialogPrimitive from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

// Off-Canvas-Panel (mobile Sidebar) auf Basis von Radix Dialog statt eines
// eigenen Pakets — gleiche Grundlage wie Dialog, nur mit Rand-Position statt
// Zentrierung.
export const Sheet = DialogPrimitive.Root;
export const SheetTrigger = DialogPrimitive.Trigger;
export const SheetClose = DialogPrimitive.Close;
export const SheetPortal = DialogPrimitive.Portal;

// Federn (kritisch gedämpft, Response 0.35 s) als Easing für Web Animations.
const SPRING = "linear(0, 0.121, 0.336, 0.536, 0.69, 0.8, 0.873, 0.921, 0.952, 0.971, 0.982, 0.99, 0.994, 0.996, 0.998, 0.999, 0.999, 1, 1)";
const PROJECTION_DECELERATION = 0.998;
const DRAG_THRESHOLD_PX = 10;

export function SheetOverlay({ className, ...props }: React.ComponentProps<typeof DialogPrimitive.Overlay>) {
  return (
    <DialogPrimitive.Overlay
      className={cn(
        "fixed inset-0 z-50 bg-black/30 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0",
        className
      )}
      {...props}
    />
  );
}

const sheetVariants = cva(
  "fixed z-50 gap-4 border-black/[0.06] bg-white/95 backdrop-blur-xl p-5 shadow-2xl",
  {
    variants: {
      side: {
        left: "inset-y-0 left-0 h-full w-72 border-r touch-pan-y data-[state=closed]:animate-out data-[state=closed]:duration-200 data-[state=closed]:slide-out-to-left",
        right: "inset-y-0 right-0 h-full w-72 border-l touch-pan-y data-[state=closed]:animate-out data-[state=closed]:duration-200 data-[state=closed]:slide-out-to-right",
      },
    },
    defaultVariants: { side: "left" },
  }
);

function prefersReducedMotion() {
  return typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Aktuelle, sichtbare X-Verschiebung (auch mitten in einer Animation). */
function currentTranslateX(el: HTMLElement) {
  const t = getComputedStyle(el).transform;
  return t && t !== "none" ? new DOMMatrixReadOnly(t).m41 : 0;
}

/**
 * Off-Canvas-Panel nach dem apple-design-Skill:
 * - öffnet per Feder,
 * - folgt dem Finger 1:1 (Wischen zum Schließen) und bleibt jederzeit
 *   unterbrechbar (neue Geste startet von der sichtbaren Position),
 * - übernimmt beim Loslassen die Geschwindigkeit: Endposition per
 *   Momentum-Projektion (x + v · d/(1−d)), danach Snap auf offen/zu,
 * - Rubber-Banding in die "falsche" Richtung,
 * - Overlay dunkelt synchron zur Position ab.
 * Schließen per Esc, Close-Button oder Overlay nutzt weiter Radix' Ausblenden.
 */
export function SheetContent({
  side = "left",
  className,
  children,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Content> & VariantProps<typeof sheetVariants>) {
  const contentRef = React.useRef<HTMLDivElement>(null);
  const overlayRef = React.useRef<HTMLDivElement>(null);
  const closeRef = React.useRef<HTMLButtonElement>(null);
  const drag = React.useRef<{
    id: number; startX: number; startOffset: number; active: boolean;
    samples: { t: number; x: number }[];
  } | null>(null);
  const sign = side === "right" ? 1 : -1; // Richtung "nach außen"

  const setOverlay = (progress: number) => {
    if (overlayRef.current) overlayRef.current.style.opacity = String(Math.max(0, Math.min(1, progress)));
  };

  const animateTo = (el: HTMLElement, to: number, then?: () => void) => {
    const from = currentTranslateX(el);
    el.getAnimations().forEach((a) => a.cancel());
    el.style.transform = `translateX(${to}px)`;
    if (prefersReducedMotion() || from === to) {
      setOverlay(to === 0 ? 1 : 0);
      then?.();
      return;
    }
    const width = el.offsetWidth;
    const anim = el.animate(
      [{ transform: `translateX(${from}px)` }, { transform: `translateX(${to}px)` }],
      { duration: 450, easing: SPRING },
    );
    overlayRef.current?.animate(
      [{ opacity: 1 - Math.min(1, Math.abs(from) / width) }, { opacity: to === 0 ? 1 : 0 }],
      { duration: 450, easing: SPRING, fill: "forwards" },
    );
    anim.onfinish = () => then?.();
  };

  // Öffnen per Feder.
  React.useLayoutEffect(() => {
    const el = contentRef.current;
    if (!el || prefersReducedMotion()) return;
    const from = sign * el.offsetWidth;
    overlayRef.current?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 450, easing: SPRING });
    el.animate(
      [{ transform: `translateX(${from}px)` }, { transform: "translateX(0px)" }],
      { duration: 450, easing: SPRING },
    );
  }, [sign]);

  const onPointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = contentRef.current;
    if (!el || (e.pointerType === "mouse" && e.button !== 0)) return;
    // Laufende Animation einfrieren: neue Geste startet an der sichtbaren Stelle.
    const visible = currentTranslateX(el);
    el.getAnimations().forEach((a) => a.cancel());
    el.style.transform = `translateX(${visible}px)`;
    drag.current = {
      id: e.pointerId, startX: e.clientX, startOffset: visible, active: false,
      samples: [{ t: performance.now(), x: e.clientX }],
    };
  };

  const onPointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = contentRef.current;
    const d = drag.current;
    if (!el || !d || d.id !== e.pointerId) return;
    let dx = e.clientX - d.startX;
    if (!d.active) {
      if (Math.abs(dx) < DRAG_THRESHOLD_PX) return;
      d.active = true;
      // Ab hier relativ zum Aktivierungspunkt, damit das Panel beim Überschreiten
      // der Schwelle nicht um 10 px springt.
      d.startX = e.clientX;
      dx = 0;
      el.setPointerCapture(e.pointerId);
    }
    d.samples.push({ t: performance.now(), x: e.clientX });
    if (d.samples.length > 8) d.samples.shift();
    let offset = d.startOffset + dx;
    // Rubber-Banding: nach innen ziehen (über die offene Position hinaus) bremst progressiv.
    const inward = offset * sign < 0;
    if (inward) offset = -sign * Math.pow(Math.abs(offset), 0.75);
    el.style.transform = `translateX(${offset}px)`;
    setOverlay(1 - Math.min(1, Math.abs(Math.max(0, offset * sign)) / el.offsetWidth));
  };

  const finishDrag = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = contentRef.current;
    const d = drag.current;
    drag.current = null;
    if (!el || !d || d.id !== e.pointerId) return;
    if (!d.active) {
      el.style.transform = "";
      return;
    }
    const now = performance.now();
    const recent = d.samples.filter((s) => now - s.t < 100);
    const first = recent[0] ?? d.samples[0];
    const last = d.samples[d.samples.length - 1];
    const velocity = last.t > first.t ? ((last.x - first.x) / (last.t - first.t)) * 1000 : 0; // px/s
    const x = currentTranslateX(el);
    const projected = x + (velocity / 1000) * (PROJECTION_DECELERATION / (1 - PROJECTION_DECELERATION));
    const closes = projected * sign > el.offsetWidth / 2;
    if (closes) {
      animateTo(el, sign * el.offsetWidth, () => {
        // Radix' eigene Ausblende-Animation würde von 0 neu starten.
        el.style.animation = "none";
        closeRef.current?.click();
      });
    } else {
      animateTo(el, 0, () => {
        el.style.transform = "";
      });
    }
  };

  return (
    <SheetPortal>
      <DialogPrimitive.Overlay
        ref={overlayRef}
        className="fixed inset-0 z-50 bg-black/30 backdrop-blur-[2px] data-[state=closed]:animate-out data-[state=closed]:fade-out-0"
      />
      <DialogPrimitive.Content
        ref={contentRef}
        className={cn(sheetVariants({ side }), className)}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={finishDrag}
        onPointerCancel={finishDrag}
        {...props}
      >
        {children}
        <DialogPrimitive.Close
          ref={closeRef}
          className="absolute right-4 top-4 rounded-full p-1 text-[#726c78] transition hover:bg-black/[0.05] hover:text-[#15131a] focus-visible:outline-none"
        >
          <X className="size-4" />
          <span className="sr-only">Schließen</span>
        </DialogPrimitive.Close>
      </DialogPrimitive.Content>
    </SheetPortal>
  );
}

export function SheetHeader({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("flex flex-col gap-1", className)} {...props} />;
}

export function SheetTitle({ className, ...props }: React.ComponentProps<typeof DialogPrimitive.Title>) {
  return <DialogPrimitive.Title className={cn("text-base font-semibold tracking-tight text-[#15131a]", className)} {...props} />;
}
