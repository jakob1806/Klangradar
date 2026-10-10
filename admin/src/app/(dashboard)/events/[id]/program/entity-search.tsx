"use client";

import { useEffect, useId, useRef, useState } from "react";
import { searchEntities, type EntityHit, type EntityKind } from "./search-actions";

// Suchfeld mit Trefferliste statt <select>: tippen filtert serverseitig über
// den gesamten Bestand, Pfeiltasten/Enter wählen, Esc schließt. Der gewählte
// Wert liegt als verstecktes Feld `name` im Formular.
export function EntitySearch({
  kind,
  name,
  placeholder,
  required,
}: {
  kind: EntityKind;
  name: string;
  placeholder: string;
  required?: boolean;
}) {
  const listId = useId();
  const [text, setText] = useState("");
  const [selected, setSelected] = useState<EntityHit | null>(null);
  const [hits, setHits] = useState<EntityHit[]>([]);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const boxRef = useRef<HTMLDivElement>(null);
  const requestId = useRef(0);

  useEffect(() => {
    if (!open || selected) return;
    const id = ++requestId.current;
    const timer = setTimeout(async () => {
      setLoading(true);
      const result = await searchEntities(kind, text).catch(() => []);
      if (id !== requestId.current) return;
      setHits(result);
      setActive(0);
      setLoading(false);
    }, 180);
    return () => clearTimeout(timer);
  }, [text, open, selected, kind]);

  useEffect(() => {
    inputRef.current?.setCustomValidity(required && !selected ? "Bitte einen Eintrag aus der Liste wählen." : "");
  }, [selected, required, text]);

  useEffect(() => {
    function onDown(event: MouseEvent) {
      if (!boxRef.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, []);

  function choose(hit: EntityHit) {
    setSelected(hit);
    setText(hit.label);
    setOpen(false);
  }

  function clear() {
    setSelected(null);
    setText("");
    setOpen(true);
    inputRef.current?.focus();
  }

  return (
    <div ref={boxRef} className="relative">
      <input type="hidden" name={name} value={selected?.id ?? ""} />
      <div className="flex items-center">
        <input
          ref={inputRef}
          type="text"
          role="combobox"
          aria-expanded={open}
          aria-controls={listId}
          aria-autocomplete="list"
          autoComplete="off"
          value={text}
          required={required}
          placeholder={placeholder}
          onFocus={() => setOpen(true)}
          onChange={(event) => {
            setText(event.target.value);
            setSelected(null);
            setOpen(true);
          }}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") { event.preventDefault(); setOpen(true); setActive((i) => Math.min(i + 1, hits.length - 1)); }
            else if (event.key === "ArrowUp") { event.preventDefault(); setActive((i) => Math.max(i - 1, 0)); }
            else if (event.key === "Enter" && open && hits[active] && !selected) { event.preventDefault(); choose(hits[active]); }
            else if (event.key === "Escape") setOpen(false);
          }}
          className="w-full border border-neutral-300 bg-white px-3 py-2 pr-8 text-sm outline-none focus:border-[#2D2A6E]"
        />
        {selected && (
          <button type="button" onClick={clear} aria-label="Auswahl entfernen" className="absolute right-2 text-neutral-400 hover:text-neutral-700">
            ×
          </button>
        )}
      </div>
      {open && !selected && (
        <ul
          id={listId}
          role="listbox"
          className="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-xl border border-neutral-200 bg-white py-1 text-sm shadow-lg"
        >
          {loading && hits.length === 0 && <li className="px-3 py-2 text-neutral-400">Suche …</li>}
          {!loading && hits.length === 0 && <li className="px-3 py-2 text-neutral-400">Keine Treffer</li>}
          {hits.map((hit, index) => (
            <li
              key={hit.id}
              role="option"
              aria-selected={index === active}
              onMouseDown={(event) => { event.preventDefault(); choose(hit); }}
              onMouseEnter={() => setActive(index)}
              className={`cursor-pointer px-3 py-1.5 ${index === active ? "bg-[#ECEBFA] text-[#2D2A6E]" : "text-neutral-800"}`}
            >
              <span className="font-medium">{hit.label}</span>
              {hit.hint && <span className="ml-2 text-xs text-neutral-500">{hit.hint}</span>}
            </li>
          ))}
          {hits.length === 25 && <li className="px-3 py-1.5 text-xs text-neutral-400">Weitertippen, um die Auswahl einzugrenzen …</li>}
        </ul>
      )}
    </div>
  );
}
