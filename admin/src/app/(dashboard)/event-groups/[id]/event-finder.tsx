"use client";

// Terminsuche für Eventgruppen (01.11.2026): ersetzt das <select> mit allen
// ungruppierten Events (bei >1000 Events abgeschnitten, keine Suche, nur
// einzeln hinzufügbar). Ohne Suchtext zeigt es Termine mit gleichem Titel
// wie die Gruppe, auch solche aus anderen Gruppen (dann markiert).

import { useEffect, useRef, useState, useTransition } from "react";
import { formatMunichDateTime } from "@/lib/munich-time";
import { addEventsToGroup, searchGroupCandidateEvents, type GroupCandidateEvent } from "./actions";

export function EventFinder({ groupId }: { groupId: string }) {
  const [query, setQuery] = useState("");
  const [includePast, setIncludePast] = useState(false);
  const [hits, setHits] = useState<GroupCandidateEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [copyLineup, setCopyLineup] = useState(true);
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(0);

  useEffect(() => {
    const id = ++requestId.current;
    const timer = setTimeout(async () => {
      setLoading(true);
      const result = await searchGroupCandidateEvents(groupId, query, includePast).catch(() => []);
      if (id !== requestId.current) return;
      setHits(result);
      setLoading(false);
    }, 200);
    return () => clearTimeout(timer);
  }, [groupId, query, includePast]);

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const allVisibleSelected = hits.length > 0 && hits.every((h) => selected.has(h.id));

  function submit() {
    setError(null);
    startTransition(async () => {
      try {
        await addEventsToGroup(groupId, [...selected], copyLineup);
        setSelected(new Set());
        setHits((prev) => prev.filter((h) => !selected.has(h.id)));
      } catch (e) {
        setError(e instanceof Error ? e.message : "Hinzufügen fehlgeschlagen.");
      }
    });
  }

  return (
    <div className="rounded-lg border border-neutral-200 bg-white p-4">
      <div className="flex flex-wrap items-center gap-3">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Termine suchen (Titel, z. B. „Tosca“) …"
          className="min-w-0 flex-1 border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-[#2D2A6E]"
          aria-label="Termine suchen"
        />
        <label className="flex items-center gap-2 text-xs text-neutral-600">
          <input type="checkbox" checked={includePast} onChange={(e) => setIncludePast(e.target.checked)} />
          Auch vergangene
        </label>
      </div>
      <p className="mt-2 text-xs text-neutral-500">
        {query.trim() ? "Suchergebnisse" : "Vorschläge: Termine mit gleichem Titel wie diese Gruppe"}
        {!loading && ` · ${hits.length}${hits.length >= 150 ? "+ (Suche verfeinern)" : ""}`}
      </p>

      <div className="mt-2 max-h-80 overflow-auto rounded border border-neutral-100">
        {loading && hits.length === 0 ? (
          <p className="px-3 py-4 text-sm text-neutral-400">Suche …</p>
        ) : hits.length === 0 ? (
          <p className="px-3 py-4 text-sm text-neutral-400">Keine passenden Termine.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-neutral-50 text-left text-xs text-neutral-500">
              <tr>
                <th className="w-8 px-3 py-1.5">
                  <input
                    type="checkbox"
                    aria-label="Alle sichtbaren auswählen"
                    checked={allVisibleSelected}
                    onChange={() =>
                      setSelected((prev) => {
                        const next = new Set(prev);
                        for (const h of hits) {
                          if (allVisibleSelected) next.delete(h.id);
                          else next.add(h.id);
                        }
                        return next;
                      })
                    }
                  />
                </th>
                <th className="px-2 py-1.5 font-medium">Datum</th>
                <th className="px-2 py-1.5 font-medium">Titel</th>
                <th className="px-2 py-1.5 font-medium">Ort</th>
              </tr>
            </thead>
            <tbody>
              {hits.map((h) => (
                <tr
                  key={h.id}
                  onClick={() => toggle(h.id)}
                  className={`cursor-pointer border-t border-neutral-100 ${selected.has(h.id) ? "bg-[#ECEBFA]" : "hover:bg-neutral-50"}`}
                >
                  <td className="px-3 py-1.5">
                    <input type="checkbox" checked={selected.has(h.id)} onChange={() => toggle(h.id)} onClick={(e) => e.stopPropagation()} aria-label={`${h.title} auswählen`} />
                  </td>
                  <td className="whitespace-nowrap px-2 py-1.5 text-neutral-700">{formatMunichDateTime(h.start_datetime)}</td>
                  <td className="px-2 py-1.5">
                    <span className="text-neutral-900">{h.title}</span>
                    {h.otherGroup && (
                      <span className="ml-2 rounded bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium text-amber-700" title="Wird beim Hinzufügen aus dieser Gruppe umgehängt">
                        in Gruppe „{h.otherGroup.title}“
                      </span>
                    )}
                  </td>
                  <td className="px-2 py-1.5 text-neutral-500">{h.venue ?? "–"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
        <label className="flex items-center gap-2 text-xs text-neutral-600">
          <input type="checkbox" checked={copyLineup} onChange={(e) => setCopyLineup(e.target.checked)} />
          Programm und Besetzung der Gruppe übernehmen
        </label>
        <button
          type="button"
          disabled={selected.size === 0 || pending}
          onClick={submit}
          className="rounded bg-[#2D2A6E] px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
        >
          {pending ? "Wird hinzugefügt …" : `${selected.size || ""} Termin${selected.size === 1 ? "" : "e"} hinzufügen`}
        </button>
      </div>
      {error && <p className="mt-2 text-sm text-red-700">{error}</p>}
    </div>
  );
}
