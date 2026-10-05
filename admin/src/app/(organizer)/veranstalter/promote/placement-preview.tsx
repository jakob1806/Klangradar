"use client";

import Image from "next/image";

export type PreviewEvent = { title: string; startLabel: string; venueName: string | null; imageUrl: string | null };

const PLACEMENT_TITLE: Record<string, string> = {
  standard: "Kalender · Tagesliste",
  featured: "Suche · Konzerte entdecken",
  local_spotlight: "Home · Heute in München",
  homepage_feature: "Home · Hero-Platzierung",
  push: "Push-Benachrichtigung",
};

// Echte Screenshots der nativen iOS-App (public/app-preview/*.jpg, 920 px
// breit, Seitenverhältnis 920×2000). Die Umgebung (Navigation, Tab-Leiste,
// übrige Kacheln = "Dummies") ist unverändert die App; nur die beworbene
// Kachel wird mit dem gewählten Event überlagert. Alle Maße unten sind
// Pixel des 920-px-Screenshots und werden in Prozent umgerechnet.
const W = 920;
const H = 2000;
const pct = (v: number, base: number) => `${(v / base) * 100}%`;
// 1 Screenshot-Pixel in "cqw" (Container-Breite) — Schriftgrößen skalieren
// so exakt mit dem Screenshot.
const px = (v: number) => `${(v / W) * 100}cqw`;

type Slot = { shot: string; x: number; y: number; w: number; h: number; bg?: string };
const SLOTS: Record<string, Slot> = {
  homepage_feature: { shot: "home", x: 46, y: 284, w: 828, h: 512 },
  local_spotlight: { shot: "home", x: 36, y: 962, w: 468, h: 450, bg: "#F6F9FE" },
  featured: { shot: "search", x: 46, y: 739, w: 544, h: 668 },
  standard: { shot: "calendar", x: 52, y: 1214, w: 816, h: 176, bg: "#FCFDFE" },
};

/** Vorschau: pro Platzierungsart der echte App-Bereich, das gewählte Event an
 * der geplanten Stelle (klein als "Anzeige" gekennzeichnet), drumherum die
 * übrigen App-Inhalte als Dummies. */
export function PlacementPreview({ placement, event }: { placement: string; event: PreviewEvent | null }) {
  const e: PreviewEvent = event ?? { title: "Dein Event", startLabel: "Mo., 5. Okt. 20:00", venueName: "Veranstaltungsort", imageUrl: null };
  const slot = SLOTS[placement];
  return (
    <div className="flex flex-col items-center gap-3">
      <div className="text-center">
        <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#2D2A6E]">Vorschau</p>
        <p className="text-sm font-semibold text-[#15131a]">{PLACEMENT_TITLE[placement] ?? placement}</p>
      </div>
      <div className="w-[280px] rounded-[40px] bg-[#18181B] p-[7px] shadow-[0_18px_40px_-12px_rgba(24,24,27,0.45)]">
        <div className="overflow-hidden rounded-[33px] bg-white">
          {slot ? (
            <div className="relative" style={{ containerType: "inline-size", aspectRatio: `${W} / ${H}` }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`/app-preview/${slot.shot}.jpg`} alt="" className="absolute inset-0 size-full" />
              <div
                className="absolute overflow-hidden"
                style={{ left: pct(slot.x, W), top: pct(slot.y, H), width: pct(slot.w, W), height: pct(slot.h, H), background: slot.bg }}
              >
                {placement === "homepage_feature" && <Hero event={e} />}
                {placement === "local_spotlight" && <RailCard event={e} />}
                {placement === "featured" && <DiscoveryCard event={e} />}
                {placement === "standard" && <CalendarRow event={e} />}
              </div>
            </div>
          ) : (
            <LockScreen event={e} />
          )}
        </div>
      </div>
      <p className="max-w-[260px] text-center text-[11px] leading-4 text-[#726c78]">
        Screenshot der Klangradar-iOS-App; nur deine Kachel ist ersetzt. Die genaue Position kann je nach Saison, Stadt und Auslastung abweichen.
      </p>
    </div>
  );
}

function Cover({ event, className = "" }: { event: PreviewEvent; className?: string }) {
  return (
    <div className={`${className.includes("absolute") ? "" : "relative"} overflow-hidden bg-gradient-to-br from-[#1b1a4a] to-[#2D2A6E] ${className}`}>
      {event.imageUrl && <Image src={event.imageUrl} alt="" fill sizes="300px" className="object-cover" unoptimized />}
    </div>
  );
}

// Wie EventArtwork in der App: winziges "Anzeige"-Label oben links.
function AdBadge({ left = 7, top = 7 }: { left?: number; top?: number }) {
  return (
    <span
      className="absolute font-bold text-white"
      style={{ left: px(left), top: px(top), fontSize: px(21), padding: `${px(6)} ${px(14)}`, background: "rgba(0,0,0,.5)", borderRadius: 999, lineHeight: 1 }}
    >
      Anzeige
    </span>
  );
}

function Heart({ right = 14, top = 14 }: { right?: number; top?: number }) {
  return (
    <span
      className="absolute flex items-center justify-center text-white"
      style={{ right: px(right), top: px(top), width: px(56), height: px(56), borderRadius: 999, background: "rgba(0,0,0,.32)", fontSize: px(30) }}
    >
      ♡
    </span>
  );
}

// HeroEventView in HomeView.swift
function Hero({ event }: { event: PreviewEvent }) {
  return (
    <div className="relative size-full" style={{ borderRadius: px(55) }}>
      <Cover event={event} className="absolute inset-0" />
      <div className="absolute inset-x-0 bottom-0" style={{ height: "72%", background: "linear-gradient(to bottom, transparent 0%, rgba(0,0,0,.16) 28%, rgba(0,0,0,.86) 100%)" }} />
      <AdBadge left={18} top={18} />
      <div className="absolute inset-x-0 bottom-0 text-white" style={{ padding: px(41), textShadow: "0 2px 7px rgba(0,0,0,.34)" }}>
        <p className="font-bold uppercase" style={{ fontSize: px(28), letterSpacing: px(1.8), opacity: 0.9 }}>{event.startLabel}</p>
        <p className="line-clamp-2 font-bold leading-[1.15]" style={{ fontSize: px(49), marginTop: px(14) }}>{event.title}</p>
        <p className="line-clamp-1 font-medium" style={{ fontSize: px(36), marginTop: px(14), opacity: 0.78 }}>📍 {event.venueName}</p>
      </div>
    </div>
  );
}

// EventCard in Home-Rails (Bild 448×250, darunter Titel und Datum)
function RailCard({ event }: { event: PreviewEvent }) {
  return (
    <div className="relative size-full">
      <div className="absolute" style={{ left: px(10), top: px(9), width: px(448), height: px(250) }}>
        <Cover event={event} className="size-full" />
        <AdBadge left={0} top={0} />
        <Heart />
      </div>
      <div className="absolute" style={{ left: px(10), top: px(285), width: px(448) }}>
        <p className="line-clamp-2 font-semibold leading-[1.22]" style={{ fontSize: px(42), color: "#000" }}>{event.title}</p>
        <p className="line-clamp-1" style={{ fontSize: px(36), color: "#8a8a8f", marginTop: px(8) }}>{event.startLabel}{event.venueName ? ` · ${event.venueName}` : ""}</p>
      </div>
    </div>
  );
}

// SearchDiscoveryEventCard in SearchView.swift (238×292 pt)
function DiscoveryCard({ event }: { event: PreviewEvent }) {
  return (
    <div className="relative size-full" style={{ borderRadius: px(50), boxShadow: "0 6px 12px rgba(0,0,0,.12)" }}>
      <Cover event={event} className="absolute inset-0" />
      <div className="absolute inset-0" style={{ background: "linear-gradient(to bottom, transparent, rgba(0,0,0,.18), rgba(0,0,0,.92))" }} />
      <AdBadge left={18} top={18} />
      <Heart right={22} top={22} />
      <div className="absolute inset-x-0 bottom-0 text-white" style={{ padding: px(37) }}>
        <p className="line-clamp-3 font-bold leading-[1.2]" style={{ fontSize: px(46) }}>{event.title}</p>
        <p className="line-clamp-2" style={{ fontSize: px(36), marginTop: px(12), opacity: 0.78 }}>{event.startLabel}{event.venueName ? ` · ${event.venueName}` : ""}</p>
      </div>
    </div>
  );
}

// CalendarEventRow in EventCalendarView.swift
function CalendarRow({ event }: { event: PreviewEvent }) {
  const time = event.startLabel.match(/\d{1,2}:\d{2}/)?.[0] ?? "";
  return (
    <div className="relative size-full">
      <div className="absolute overflow-hidden" style={{ left: px(24), top: px(29), width: px(118), height: px(118), borderRadius: px(28) }}>
        <Cover event={event} className="size-full" />
        <AdBadge left={0} top={0} />
      </div>
      <div className="absolute" style={{ left: px(171), top: px(18), right: px(64) }}>
        <p className="font-bold" style={{ fontSize: px(32), color: "#1a5f9a" }}>{time || "–"}</p>
        <p className="line-clamp-2 font-semibold leading-[1.15]" style={{ fontSize: px(44), color: "#000", marginTop: px(6) }}>{event.title}</p>
        <p className="line-clamp-1" style={{ fontSize: px(34), color: "#8a8a8f", marginTop: px(6) }}>{event.venueName}</p>
      </div>
      <span className="absolute text-[#c4c4c8]" style={{ right: px(26), top: px(70), fontSize: px(40) }}>›</span>
    </div>
  );
}

// Push: iOS-Systemoberfläche (Sperrbildschirm), kein Teil der App-UI.
function LockScreen({ event }: { event: PreviewEvent }) {
  return (
    <div className="flex h-[560px] flex-col items-center bg-gradient-to-b from-[#3b3a6e] via-[#26254f] to-[#15142f] text-white">
      <p className="mt-14 text-[11px] font-semibold text-white/80">Montag, 5. Oktober</p>
      <p className="text-[54px] font-light leading-[58px]">9:41</p>
      <div className="mt-8 w-[236px] rounded-[20px] bg-white/20 p-3 backdrop-blur">
        <div className="flex items-center gap-2">
          <Image src="/app-logo.svg" alt="" width={18} height={18} className="rounded-[5px]" />
          <span className="text-[9px] font-semibold uppercase tracking-wide text-white/80">Klangradar</span>
          <span className="ml-auto text-[9px] text-white/70">jetzt</span>
        </div>
        <p className="mt-1.5 line-clamp-2 text-[11px] font-bold leading-4">Neu für dich: {event.title}</p>
        <p className="mt-0.5 line-clamp-2 text-[10px] leading-[13px] text-white/90">{event.startLabel}{event.venueName ? ` · ${event.venueName}` : ""}</p>
      </div>
    </div>
  );
}
