"use client";

// Erstellt von Claude Code (14.11.2026): Zusätze zur Seitenleiste –
// Zahlen-Plaketten (offene Aufgaben), angeheftete Seiten und Tastenkürzel.
import { useEffect, useState, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { ALL_NAV_LINKS, NAV_SHORTCUTS, type NavArea } from "@/components/nav-groups";
import { getNavCounts } from "@/lib/nav-counts";

// ---------- Zahlen-Plaketten ----------

const COUNTS_KEY = "klangradar.sidebar.counts";
const COUNTS_MAX_AGE = 2 * 60 * 1000;
let countsPromise: Promise<Record<string, number>> | null = null;

function cachedCounts(): { at: number; counts: Record<string, number> } | null {
  try {
    const raw = window.sessionStorage.getItem(COUNTS_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { at: number; counts: Record<string, number> };
    return typeof parsed?.at === "number" && parsed.counts ? parsed : null;
  } catch {
    return null;
  }
}

export function useNavCounts(): Record<string, number> {
  const [counts, setCounts] = useState<Record<string, number>>({});
  useEffect(() => {
    let alive = true;
    const load = async () => {
      await Promise.resolve();
      if (!alive) return;
      const cached = cachedCounts();
      if (cached) setCounts(cached.counts);
      if (cached && Date.now() - cached.at < COUNTS_MAX_AGE) return;
      countsPromise ??= getNavCounts().finally(() => { countsPromise = null; });
      countsPromise
        .then((next) => {
          if (!alive) return;
          setCounts(next);
          try { window.sessionStorage.setItem(COUNTS_KEY, JSON.stringify({ at: Date.now(), counts: next })); } catch { /* egal */ }
        })
        .catch(() => { /* Plaketten sind optional */ });
    };
    void load();
    const timer = window.setInterval(() => void load(), COUNTS_MAX_AGE);
    return () => { alive = false; window.clearInterval(timer); };
  }, []);
  return counts;
}

/** Summe eines Bereichs: Eingang zählt selbst, sonst alle Reiter zusammen. */
export function areaCount(area: NavArea, counts: Record<string, number>): number {
  if (area.href === "/eingang") return counts["/eingang"] ?? 0;
  let sum = 0;
  for (const href of new Set([area.href, ...(area.tabs ?? []).map((t) => t.href)])) sum += counts[href] ?? 0;
  return sum;
}

export function CountBadge({ value }: { value: number }) {
  if (!value) return null;
  return (
    <span className="ml-auto shrink-0 rounded-full bg-[#2D2A6E]/10 px-1.5 py-px text-[11px] font-semibold tabular-nums text-[#2D2A6E]">
      {value > 999 ? "999+" : value.toLocaleString("de-DE")}
    </span>
  );
}

// ---------- Angeheftet ----------

const PINS_KEY = "klangradar.sidebar.pins";
const PINS_EVENT = "klangradar-sidebar-pins";
const VALID = new Set(ALL_NAV_LINKS.map((l) => l.href));

function subscribePins(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(PINS_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(PINS_EVENT, onChange);
  };
}

function readPinsRaw() {
  try { return window.localStorage.getItem(PINS_KEY) ?? "[]"; } catch { return "[]"; }
}

export function usePins(): [string[], (href: string) => void] {
  const raw = useSyncExternalStore(subscribePins, readPinsRaw, () => "[]");
  let pins: string[] = [];
  try {
    const parsed: unknown = JSON.parse(raw);
    // Nur bekannte Navigationspfade – localStorage ist Nutzereingabe.
    pins = Array.isArray(parsed) ? parsed.filter((h): h is string => typeof h === "string" && VALID.has(h)) : [];
  } catch { pins = []; }
  const toggle = (href: string) => {
    const next = pins.includes(href) ? pins.filter((h) => h !== href) : [...pins, href].slice(-8);
    try {
      window.localStorage.setItem(PINS_KEY, JSON.stringify(next));
      window.dispatchEvent(new Event(PINS_EVENT));
    } catch { /* ohne localStorage kein Anheften */ }
  };
  return [pins, toggle];
}

// ---------- Tastenkürzel ----------

function isTyping(target: EventTarget | null) {
  const el = target as HTMLElement | null;
  if (!el) return false;
  return el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName);
}

export function NavShortcuts() {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [help, setHelp] = useState(false);

  useEffect(() => {
    let timer: number | undefined;
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey || isTyping(event.target)) return;
      if (event.key === "Escape") { setHelp(false); setPending(false); return; }
      if (event.key === "?") { event.preventDefault(); setHelp((v) => !v); return; }
      if (pending) {
        const target = NAV_SHORTCUTS[event.key.toLowerCase()];
        setPending(false);
        window.clearTimeout(timer);
        if (target) { event.preventDefault(); router.push(target.href); }
        return;
      }
      if (event.key === "g") {
        setPending(true);
        timer = window.setTimeout(() => setPending(false), 1500);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => { window.removeEventListener("keydown", onKey); window.clearTimeout(timer); };
  }, [pending, router]);

  return (
    <>
      {pending && (
        <div className="fixed bottom-4 left-1/2 z-50 -translate-x-1/2 rounded-full bg-[#111111] px-4 py-2 text-[13px] text-white shadow-lg">
          g … {Object.entries(NAV_SHORTCUTS).map(([k, v]) => `${k} ${v.label}`).join(" · ")}
        </div>
      )}
      {help && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30" onClick={() => setHelp(false)}>
          <div className="w-[360px] rounded-2xl bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <h2 className="mb-3 text-[15px] font-semibold">Tastenkürzel</h2>
            <ul className="space-y-1.5 text-[13px]">
              <li className="flex justify-between"><span>Suche (Seiten & Datensätze)</span><kbd className="font-mono">⌘ K</kbd></li>
              {Object.entries(NAV_SHORTCUTS).map(([key, value]) => (
                <li key={key} className="flex justify-between"><span>{value.label}</span><kbd className="font-mono">g {key}</kbd></li>
              ))}
              <li className="flex justify-between"><span>Diese Hilfe</span><kbd className="font-mono">?</kbd></li>
            </ul>
          </div>
        </div>
      )}
    </>
  );
}
