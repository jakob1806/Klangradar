"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ALL_NAV_LINKS } from "@/components/nav-groups";
import { ORGANIZER_NAV_LINKS } from "@/components/organizer/nav-links";
import { searchCommandEntities, type CommandHit } from "@/lib/command-search";

// ⌘K / Strg+K: Seiten und (im Admin) Datensätze anspringen.
// Erstellt von Claude Code (Nutzerwunsch 30.10.2026).
const OPEN_EVENT = "klangradar-command-palette";

export function openCommandPalette() {
  window.dispatchEvent(new Event(OPEN_EVENT));
}

export function CommandPaletteButton() {
  return (
    <button
      type="button"
      onClick={openCommandPalette}
      className="mx-0.5 flex items-center justify-between rounded-lg border border-[#DADADA] bg-white px-3 py-1.5 text-[13px] text-[#6B6B6B] hover:border-[#111111]"
    >
      <span>Suchen & springen …</span>
      <kbd className="rounded border border-[#E5E5E5] px-1.5 text-[11px]">⌘K</kbd>
    </button>
  );
}

export function CommandPalette({ scope }: { scope: "admin" | "organizer" }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [entityHits, setEntityHits] = useState<CommandHit[]>([]);
  const [index, setIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const token = useRef(0);

  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const show = () => {
      setQuery("");
      setEntityHits([]);
      setIndex(0);
      setOpen(true);
      setTimeout(() => inputRef.current?.focus(), 0);
    };
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        show();
      } else if (event.key === "Escape") {
        setOpen(false);
      }
    };
    const onOpen = show;
    window.addEventListener("keydown", onKey);
    window.addEventListener(OPEN_EVENT, onOpen);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener(OPEN_EVENT, onOpen);
    };
  }, []);

  function changeQuery(value: string) {
    setQuery(value);
    setIndex(0);
    if (scope !== "admin") return;
    const current = ++token.current;
    if (timer.current) clearTimeout(timer.current);
    if (value.trim().length < 2) {
      setEntityHits([]);
      return;
    }
    timer.current = setTimeout(async () => {
      const hits = await searchCommandEntities(value).catch(() => []);
      if (current === token.current) setEntityHits(hits);
    }, 200);
  }

  const pages = useMemo(() => {
    const links = scope === "admin"
      ? ALL_NAV_LINKS.map((l) => ({ href: l.href, label: l.label, detail: l.area === l.label ? l.group : `${l.group} · ${l.area}` }))
      : ORGANIZER_NAV_LINKS.map((l) => ({ href: l.href, label: l.label, detail: l.group }));
    const q = query.trim().toLowerCase();
    return (q ? links.filter((l) => `${l.label} ${l.detail}`.toLowerCase().includes(q)) : links).slice(0, q ? 8 : 12);
  }, [query, scope]);

  const results = [...pages, ...entityHits];

  if (!open) return null;

  const go = (href: string) => {
    setOpen(false);
    router.push(href);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/25 px-4 pt-[12vh]" onClick={() => setOpen(false)}>
      <div
        role="dialog"
        aria-label="Suchen und springen"
        className="w-full max-w-xl overflow-hidden rounded-xl border border-[#EAEAEA] bg-white shadow-2xl"
        onClick={(event) => event.stopPropagation()}
      >
        <input
          ref={inputRef}
          value={query}
          onChange={(event) => changeQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") {
              event.preventDefault();
              setIndex((i) => Math.min(i + 1, results.length - 1));
            } else if (event.key === "ArrowUp") {
              event.preventDefault();
              setIndex((i) => Math.max(i - 1, 0));
            } else if (event.key === "Enter" && results[index]) {
              go(results[index].href);
            }
          }}
          placeholder={scope === "admin" ? "Seite, Person, Ensemble, Werk, Termin …" : "Seite suchen …"}
          className="w-full border-b border-[#EAEAEA] px-4 py-3 text-[15px] outline-none"
        />
        <ul className="max-h-[50vh] overflow-y-auto py-1">
          {results.map((result, i) => (
            <li key={`${result.href}-${i}`}>
              <button
                type="button"
                onMouseEnter={() => setIndex(i)}
                onClick={() => go(result.href)}
                className={`flex w-full items-center justify-between gap-3 px-4 py-2 text-left text-[13.5px] ${i === index ? "bg-[#2D2A6E]/[0.07]" : ""}`}
              >
                <span className="truncate text-[#111111]">{result.label}</span>
                <span className="shrink-0 text-[12px] text-[#6B6B6B]">{result.detail}</span>
              </button>
            </li>
          ))}
          {results.length === 0 && <li className="px-4 py-3 text-[13px] text-[#6B6B6B]">Nichts gefunden.</li>}
        </ul>
      </div>
    </div>
  );
}
