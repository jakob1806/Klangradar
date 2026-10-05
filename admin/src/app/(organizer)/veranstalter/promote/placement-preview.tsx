"use client";

import Image from "next/image";
import type { ReactNode } from "react";

export type PreviewEvent = { title: string; startLabel: string; venueName: string | null; imageUrl: string | null };

const DUMMIES = [
  { title: "Sinfoniekonzert", meta: "Fr., 18. Okt. · Philharmonie" },
  { title: "Liederabend", meta: "Sa., 19. Okt. · Prinzregententheater" },
  { title: "Orgelkonzert", meta: "So., 20. Okt. · St. Michael" },
  { title: "Kammermusik", meta: "Mo., 21. Okt. · Gasteig" },
];

const PLACEMENT_TITLE: Record<string, string> = {
  standard: "Event-Liste",
  featured: "Entdecken-Bereich",
  local_spotlight: "Startseite · Local Spotlight",
  homepage_feature: "Startseite · Hero-Platzierung",
  push: "Push-Benachrichtigung",
};

/** Vereinfachte Simulation der App: pro Platzierungsart der betreffende
 * Bereich, das gewählte Event an der geplanten Stelle (klein als "Anzeige" gekennzeichnet, wie in der App),
 * der Rest sind Platzhalter. Keine Live-Daten, nur zur Orientierung. */
export function PlacementPreview({ placement, event }: { placement: string; event: PreviewEvent | null }) {
  const e: PreviewEvent = event ?? { title: "Dein Event", startLabel: "Datum · Uhrzeit", venueName: "Veranstaltungsort", imageUrl: null };
  return (
    <div className="flex flex-col items-center gap-3">
      <div className="text-center">
        <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#2D2A6E]">Vorschau</p>
        <p className="text-sm font-semibold text-[#15131a]">{PLACEMENT_TITLE[placement] ?? placement}</p>
      </div>
      <Phone dark={placement === "push"}>
        {placement === "standard" && <StandardList event={e} />}
        {placement === "featured" && <FeaturedDiscover event={e} />}
        {placement === "local_spotlight" && <LocalSpotlight event={e} />}
        {placement === "homepage_feature" && <HomeHero event={e} />}
        {placement === "push" && <LockScreen event={e} />}
      </Phone>
      <p className="max-w-[260px] text-center text-[11px] leading-4 text-[#726c78]">
        Nachgebaut nach der iOS-App; Dummies füllen den Rest. Die genaue Position kann je nach Saison, Stadt und Auslastung leicht abweichen.
      </p>
    </div>
  );
}

function Phone({ children, dark }: { children: ReactNode; dark?: boolean }) {
  return (
    <div className="w-[262px] rounded-[38px] bg-[#18181B] p-[7px] shadow-[0_18px_40px_-12px_rgba(24,24,27,0.45)]">
      <div className={`relative h-[500px] overflow-hidden rounded-[32px] ${dark ? "bg-gradient-to-b from-[#3b3a6e] via-[#26254f] to-[#15142f]" : "bg-[#f4f8fd]"}`}>
        <div className="absolute left-1/2 top-2 z-20 h-[18px] w-[72px] -translate-x-1/2 rounded-full bg-black" />
        {children}
      </div>
    </div>
  );
}

function Bar({ w = "100%", h = 8, className = "" }: { w?: string; h?: number; className?: string }) {
  return <div className={`rounded-full bg-[#18181B]/10 ${className}`} style={{ width: w, height: h }} />;
}

function Cover({ event, className = "" }: { event: PreviewEvent; className?: string }) {
  return (
    <div className={`relative overflow-hidden bg-gradient-to-br from-[#2D2A6E] to-[#6a67c9] ${className}`}>
      {event.imageUrl && <Image src={event.imageUrl} alt="" fill sizes="260px" className="object-cover" unoptimized />}
    </div>
  );
}

/** Wie in der App (EventArtwork): winziges "Anzeige"-Label oben links in der Kachel. */
function AdBadge({ small }: { small?: boolean }) {
  return (
    <span className={`rounded-full bg-black/50 font-bold text-white ${small ? "px-1 py-[1px] text-[5px]" : "px-1.5 py-[2px] text-[7px]"}`}>
      Anzeige
    </span>
  );
}

function AppHeader() {
  return (
    <div className="flex items-center justify-between px-4 pb-2 pt-10">
      <span className="text-[13px] font-extrabold text-[#18181B]">Klangradar</span>
      <span className="rounded-full border border-[#18181B]/10 bg-white px-2 py-[3px] text-[8px] font-semibold text-[#0b5d93]">München ⌄</span>
    </div>
  );
}

function TabBar({ active }: { active: number }) {
  const labels = ["Home", "Suche", "Karte", "Kalender", "Profil"];
  return (
    <div className="absolute inset-x-3 bottom-3 flex justify-between rounded-full border border-[#18181B]/10 bg-white/90 px-3 py-2 shadow-sm backdrop-blur">
      {labels.map((label, i) => (
        <span key={label} className={`text-[8px] font-semibold ${i === active ? "text-[#0b5d93]" : "text-[#18181B]/55"}`}>
          {label}
        </span>
      ))}
    </div>
  );
}

function DummyCard() {
  return (
    <div className="w-[104px] shrink-0">
      <div className="h-[64px] rounded-xl bg-[#18181B]/[0.07]" />
      <Bar w="80%" h={7} className="mt-2" />
      <Bar w="60%" h={6} className="mt-1.5 opacity-70" />
    </div>
  );
}

function PromotedCard({ event, wide }: { event: PreviewEvent; wide?: boolean }) {
  return (
    <div className={`${wide ? "w-[150px]" : "w-[104px]"} shrink-0`}>
      <div className="relative">
        <Cover event={event} className={`${wide ? "h-[92px]" : "h-[64px]"} rounded-xl`} />
        <span className="absolute left-1.5 top-1.5"><AdBadge /></span>
      </div>
      <p className="mt-1.5 line-clamp-2 text-[9px] font-bold leading-3 text-[#18181B]">{event.title}</p>
      <p className="line-clamp-1 text-[8px] text-[#18181B]/55">{event.startLabel}</p>
    </div>
  );
}

function HomeHero({ event }: { event: PreviewEvent }) {
  return (
    <div className="h-full">
      <AppHeader />
      <div className="relative mx-3 h-[190px] overflow-hidden rounded-[24px]">
        <Cover event={event} className="absolute inset-0" />
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />
        <span className="absolute left-3 top-3"><AdBadge /></span>
        <div className="absolute inset-x-3 bottom-3 text-white">
          <p className="text-[8px] font-bold uppercase tracking-widest text-white/85">{event.startLabel}</p>
          <p className="line-clamp-2 text-[14px] font-bold leading-4">{event.title}</p>
          <p className="mt-0.5 line-clamp-1 text-[9px] text-white/85">{event.venueName}</p>
        </div>
      </div>
      <p className="mt-4 px-4 text-[11px] font-extrabold text-[#18181B]">Heute in München</p>
      <div className="mt-2 flex gap-2 overflow-hidden px-4"><DummyCard /><DummyCard /><DummyCard /></div>
      <p className="mt-4 px-4 text-[11px] font-extrabold text-[#18181B]">Für dich</p>
      <div className="mt-2 flex gap-2 overflow-hidden px-4"><DummyCard /><DummyCard /><DummyCard /></div>
      <TabBar active={0} />
    </div>
  );
}

function LocalSpotlight({ event }: { event: PreviewEvent }) {
  return (
    <div className="h-full">
      <AppHeader />
      <div className="mx-3 h-[78px] rounded-[18px] bg-[#18181B]/[0.07]" />
      <p className="mt-4 px-4 text-[11px] font-extrabold text-[#18181B]">Heute in München</p>
      <div className="mt-2 flex gap-2 overflow-hidden px-4"><DummyCard /><DummyCard /><DummyCard /></div>
      <p className="mt-4 px-4 text-[11px] font-extrabold text-[#18181B]">Local Spotlight · München</p>
      <div className="mt-2 flex gap-2 overflow-hidden px-4"><PromotedCard event={event} wide /><DummyCard /></div>
      <p className="mt-4 px-4 text-[11px] font-extrabold text-[#18181B]">Beliebt in München</p>
      <div className="mt-2 flex gap-2 overflow-hidden px-4"><DummyCard /><DummyCard /><DummyCard /></div>
      <TabBar active={0} />
    </div>
  );
}

function FeaturedDiscover({ event }: { event: PreviewEvent }) {
  return (
    <div className="h-full">
      <div className="px-4 pb-2 pt-10 text-[13px] font-extrabold text-[#18181B]">Suche</div>
      <div className="mx-3 flex h-[28px] items-center rounded-full bg-[#18181B]/[0.07] px-3"><Bar w="45%" h={6} /></div>
      <p className="mt-3 px-4 text-[11px] font-extrabold text-[#18181B]">Alles entdecken</p>
      <div className="mt-2 grid grid-cols-2 gap-2 px-3">
        <div className="h-[46px] rounded-xl bg-[#6366f1]/70" /><div className="h-[46px] rounded-xl bg-[#d946ef]/70" />
      </div>
      <p className="mt-3 px-4 text-[11px] font-extrabold text-[#18181B]">Konzerte entdecken</p>
      <div className="mt-2 flex gap-2 overflow-hidden px-3">
        <div className="w-[150px] shrink-0">
          <div className="relative">
            <Cover event={event} className="h-[184px] rounded-[18px]" />
            <div className="absolute inset-0 rounded-[18px] bg-gradient-to-t from-black/75 via-transparent to-transparent" />
            <span className="absolute left-2 top-2"><AdBadge /></span>
            <span className="absolute right-2 top-2 flex size-4 items-center justify-center rounded-full bg-black/30 text-[8px] text-white">♡</span>
            <div className="absolute inset-x-2.5 bottom-2.5 text-white">
              <p className="line-clamp-2 text-[11px] font-bold leading-[13px]">{event.title}</p>
              <p className="mt-0.5 line-clamp-1 text-[8px] text-white/85">{event.startLabel}</p>
            </div>
          </div>
        </div>
        <div className="w-[150px] shrink-0"><div className="h-[190px] rounded-[18px] bg-[#18181B]/[0.07]" /></div>
      </div>
      <TabBar active={1} />
    </div>
  );
}

function StandardList({ event }: { event: PreviewEvent }) {
  return (
    <div className="h-full">
      <AppHeader />
      <p className="px-4 pb-2 pt-1 text-[11px] font-extrabold text-[#18181B]">Demnächst in München</p>
      <div className="flex flex-col gap-2 px-3">
        <div className="relative flex items-center gap-2.5 rounded-2xl bg-white p-2">
          <div className="relative shrink-0">
            <Cover event={event} className="h-[52px] w-[52px] rounded-xl" />
            <span className="absolute left-0.5 top-0.5"><AdBadge small /></span>
          </div>
          <div className="min-w-0 flex-1">
            <p className="line-clamp-2 text-[10px] font-bold leading-3 text-[#18181B]">{event.title}</p>
            <p className="mt-0.5 line-clamp-1 text-[8px] text-[#18181B]/55">{event.startLabel}{event.venueName ? ` · ${event.venueName}` : ""}</p>
          </div>
        </div>
        {DUMMIES.map((d) => (
          <div key={d.title} className="flex items-center gap-2.5 rounded-2xl bg-white/80 p-2">
            <div className="h-[52px] w-[52px] shrink-0 rounded-xl bg-[#18181B]/[0.07]" />
            <div className="min-w-0 flex-1"><Bar w="70%" h={8} /><Bar w="90%" h={6} className="mt-2 opacity-70" /></div>
          </div>
        ))}
      </div>
      <TabBar active={0} />
    </div>
  );
}

function LockScreen({ event }: { event: PreviewEvent }) {
  return (
    <div className="flex h-full flex-col items-center text-white">
      <p className="mt-14 text-[11px] font-semibold text-white/80">Montag, 5. Oktober</p>
      <p className="text-[54px] font-light leading-[58px]">9:41</p>
      <div className="mt-8 w-[236px] rounded-[20px] bg-white/20 p-3 backdrop-blur">
        <div className="flex items-center gap-2">
          <span className="flex h-[18px] w-[18px] items-center justify-center rounded-[5px] bg-[#2D2A6E] text-[10px] font-extrabold text-white">K</span>
          <span className="text-[9px] font-semibold uppercase tracking-wide text-white/80">Klangradar</span>
          <span className="ml-auto text-[9px] text-white/70">jetzt</span>
        </div>
        <p className="mt-1.5 line-clamp-2 text-[11px] font-bold leading-4">Neu für dich: {event.title}</p>
        <p className="mt-0.5 line-clamp-2 text-[10px] leading-[13px] text-white/90">{event.startLabel}{event.venueName ? ` · ${event.venueName}` : ""}</p>
      </div>
      <div className="mt-2 w-[236px] rounded-[20px] bg-white/10 p-3 opacity-60">
        <Bar w="50%" h={7} className="bg-white/40" /><Bar w="80%" h={6} className="mt-2 bg-white/30" />
      </div>
    </div>
  );
}
