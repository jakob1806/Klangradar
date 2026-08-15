"use client";

import { useMemo, useState } from "react";

export function GenrePicker({
  genres,
  initialIds = [],
}: {
  genres: { id: string; label_de: string }[];
  initialIds?: string[];
}) {
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(() => new Set(initialIds));
  const [created, setCreated] = useState<string[]>([]);
  const needle = query.trim().toLocaleLowerCase("de");
  const visible = useMemo(
    () => genres.filter((genre) => !needle || genre.label_de.toLocaleLowerCase("de").includes(needle)),
    [genres, needle],
  );
  const exactExists = genres.some((genre) => genre.label_de.toLocaleLowerCase("de") === needle)
    || created.some((label) => label.toLocaleLowerCase("de") === needle);

  function addGenre() {
    const label = query.trim();
    if (!label || exactExists) return;
    setCreated((current) => [...current, label]);
    setQuery("");
  }

  return (
    <div className="rounded-2xl border border-black/[0.08] bg-white p-3 shadow-sm">
      {[...selected].map((id) => <input key={id} type="hidden" name="genre_ids" value={id} />)}
      {created.map((label) => <input key={label} type="hidden" name="new_genres" value={label} />)}
      <div className="flex gap-2">
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && needle && !exactExists) {
              event.preventDefault();
              addGenre();
            }
          }}
          placeholder="Genre suchen oder neu eingeben …"
          className="min-w-0 flex-1 rounded-xl border border-black/10 bg-neutral-50 px-3 py-2 text-sm outline-none focus:border-[#0071e3] focus:ring-2 focus:ring-[#0071e3]/15"
        />
        {needle && !exactExists && (
          <button type="button" onClick={addGenre} className="rounded-xl bg-[#0071e3] px-3 py-2 text-sm font-medium text-white">
            „{query.trim()}“ anlegen
          </button>
        )}
      </div>
      <div className="mt-3 flex max-h-44 flex-wrap gap-2 overflow-y-auto">
        {visible.map((genre) => {
          const active = selected.has(genre.id);
          return (
            <button
              key={genre.id}
              type="button"
              onClick={() => setSelected((current) => {
                const next = new Set(current);
                if (active) next.delete(genre.id); else next.add(genre.id);
                return next;
              })}
              className={`rounded-full px-3 py-1.5 text-sm transition-colors ${active ? "bg-[#0071e3] text-white" : "bg-black/[0.05] text-neutral-700 hover:bg-black/[0.09]"}`}
            >
              {active ? "✓ " : ""}{genre.label_de}
            </button>
          );
        })}
        {created.map((label) => (
          <button key={label} type="button" onClick={() => setCreated((items) => items.filter((item) => item !== label))} className="rounded-full bg-emerald-100 px-3 py-1.5 text-sm text-emerald-800">
            Neu: {label} ×
          </button>
        ))}
        {visible.length === 0 && created.length === 0 && <p className="py-2 text-sm text-neutral-400">Kein bestehendes Genre gefunden.</p>}
      </div>
    </div>
  );
}
