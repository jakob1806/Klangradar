"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { GalleryEditor } from "@/components/entity-gallery/gallery-editor";
import type { GalleryImage } from "@/lib/gallery-actions";
import {
  getWorkGalleryImages,
  listWorksWithGalleryImages,
  listVenuesForSelect,
  searchWorks,
  type LinkedWorkImageResult,
  type VenueOption,
  type WorkSearchResult,
} from "@/lib/work-search-actions";

/** Manuelle Werk-Bild-Verknüpfung: Werk per Titelsuche finden, dann Bilder
 * hochladen oder per Link hinzufügen — Nutzervorgabe "werk bild
 * verknüpfungen sollen auch manuell erstellt werden ... mehrere bilder
 * hochladen und auch über link". Kein eigenes /works-Verwaltungsmodul,
 * bewusst nur ein Suchfeld auf dieser Seite (Nutzerentscheidung). */
export function WorkImageManualLink() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<WorkSearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [selected, setSelected] = useState<WorkSearchResult | null>(null);
  const [images, setImages] = useState<GalleryImage[] | null>(null);
  const [venues, setVenues] = useState<VenueOption[]>([]);
  const [uploadVenueId, setUploadVenueId] = useState<string>("");
  const [linkedWorks, setLinkedWorks] = useState<LinkedWorkImageResult[]>([]);
  const [linkedQuery, setLinkedQuery] = useState("");
  const [linkedLoading, setLinkedLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const editorRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Venue-Auswahl ist eine Zusatzfunktion — schlägt sie fehl, bleibt die
    // Werk-Bild-Verknüpfung trotzdem nutzbar (werkweit statt venue-spezifisch).
    Promise.all([
      listVenuesForSelect().then(setVenues).catch(() => {}),
      listWorksWithGalleryImages()
        .then(setLinkedWorks)
        .catch((e) => setError(e instanceof Error ? e.message : "Bestehende Verknüpfungen konnten nicht geladen werden."))
        .finally(() => setLinkedLoading(false)),
    ]);
  }, []);

  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    const trimmed = query.trim();
    debounceRef.current = setTimeout(() => {
      if (trimmed.length < 2) {
        setResults([]);
        return;
      }
      setSearching(true);
      searchWorks(trimmed)
        .then(setResults)
        .catch((e) => setError(e instanceof Error ? e.message : "Suche fehlgeschlagen."))
        .finally(() => setSearching(false));
    }, 300);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [query]);

  function loadImages(workId: string) {
    setError(null);
    getWorkGalleryImages(workId)
      .then(setImages)
      .catch((e) => setError(e instanceof Error ? e.message : "Bilder konnten nicht geladen werden."));
  }

  function refreshLinkedWorks() {
    listWorksWithGalleryImages()
      .then(setLinkedWorks)
      .catch((e) => setError(e instanceof Error ? e.message : "Bestehende Verknüpfungen konnten nicht aktualisiert werden."));
  }

  function handleSelect(work: WorkSearchResult, scrollToEditor = false) {
    setSelected(work);
    setResults([]);
    setQuery("");
    setImages(null);
    setUploadVenueId("");
    loadImages(work.id);
    if (scrollToEditor) {
      requestAnimationFrame(() => editorRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }));
    }
  }

  const normalizedLinkedQuery = linkedQuery.trim().toLocaleLowerCase("de-DE");
  const visibleLinkedWorks = normalizedLinkedQuery
    ? linkedWorks.filter((work) =>
        `${work.title} ${work.composerName ?? ""}`.toLocaleLowerCase("de-DE").includes(normalizedLinkedQuery),
      )
    : linkedWorks;

  return (
    <div ref={editorRef} className="rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm scroll-mt-6">
      <h2 className="text-sm font-semibold text-neutral-900">Bild manuell einem Werk zuordnen</h2>
      <p className="mt-1 text-xs text-neutral-500">
        Werk suchen, dann Bilder hochladen oder per Link hinzufügen — dieses Bild wird für die automatische
        Werk-Bild-Verknüpfung berücksichtigt.
      </p>

      {selected ? (
        <div className="mt-3">
          <div className="flex items-center justify-between">
            <p className="text-sm font-medium text-neutral-900">
              {selected.title}
              {selected.composerName && <span className="font-normal text-neutral-500"> · {selected.composerName}</span>}
            </p>
            <button
              type="button"
              onClick={() => {
                setSelected(null);
                setImages(null);
              }}
              className="text-xs font-medium text-neutral-500 hover:text-neutral-800"
            >
              Anderes Werk wählen
            </button>
          </div>
          <div className="mt-3">
            {images === null ? (
              <p className="text-xs text-neutral-400">Lädt…</p>
            ) : (
              <>
                <label className="mb-2 flex items-center gap-2 text-xs text-neutral-600">
                  Venue für neu hinzugefügte Bilder:
                  <select
                    value={uploadVenueId}
                    onChange={(e) => setUploadVenueId(e.target.value)}
                    className="rounded-md border border-neutral-300 px-1.5 py-1 text-xs"
                  >
                    <option value="">Alle Venues (werkweit)</option>
                    {venues.map((v) => (
                      <option key={v.id} value={v.id}>
                        {v.name}
                      </option>
                    ))}
                  </select>
                </label>
                <GalleryEditor
                  originType="work"
                  originId={selected.id}
                  path="/work-image-reuse"
                  images={images}
                  onChanged={() => {
                    loadImages(selected.id);
                    refreshLinkedWorks();
                  }}
                  venueId={uploadVenueId || null}
                  venues={venues}
                />
              </>
            )}
          </div>
        </div>
      ) : (
        <div className="relative mt-3 max-w-sm">
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Werktitel suchen…"
            className="w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
          />
          {searching && <p className="mt-1 text-xs text-neutral-400">Sucht…</p>}
          {results.length > 0 && (
            <ul className="absolute z-10 mt-1 w-full rounded-md border border-neutral-200 bg-white shadow-lg">
              {results.map((work) => (
                <li key={work.id}>
                  <button
                    type="button"
                    onClick={() => handleSelect(work)}
                    className="block w-full px-3 py-2 text-left text-sm hover:bg-neutral-50"
                  >
                    {work.title}
                    {work.composerName && <span className="text-neutral-500"> · {work.composerName}</span>}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}

      <div className="mt-6 border-t border-neutral-200 pt-5">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="text-sm font-semibold text-neutral-900">
              Bereits verknüpfte Werke{!linkedLoading && ` (${linkedWorks.length})`}
            </h2>
            <p className="mt-1 text-xs text-neutral-500">
              Ein Werk auswählen, um Bilder, Reihenfolge, Zuschnitt oder Venue-Zuordnung zu bearbeiten.
            </p>
          </div>
          <input
            type="search"
            value={linkedQuery}
            onChange={(e) => setLinkedQuery(e.target.value)}
            placeholder="Verknüpfte Werke suchen…"
            className="w-full rounded-md border border-neutral-300 px-2.5 py-1.5 text-sm sm:w-72"
          />
        </div>

        {linkedLoading ? (
          <p className="mt-4 text-xs text-neutral-400">Verknüpfungen werden geladen…</p>
        ) : visibleLinkedWorks.length === 0 ? (
          <p className="mt-4 text-sm text-neutral-500">
            {linkedWorks.length === 0 ? "Noch keine Werke mit Werkbildern vorhanden." : "Keine passenden Werke gefunden."}
          </p>
        ) : (
          <div className="mt-4 grid max-h-[32rem] grid-cols-1 gap-2 overflow-y-auto pr-1 sm:grid-cols-2 xl:grid-cols-3">
            {visibleLinkedWorks.map((work) => (
              <button
                key={work.id}
                type="button"
                onClick={() => handleSelect(work, true)}
                className={`flex min-w-0 items-center gap-3 rounded-lg border p-2.5 text-left transition-colors hover:border-[#0071e3]/40 hover:bg-blue-50/40 ${
                  selected?.id === work.id ? "border-[#0071e3] bg-blue-50" : "border-neutral-200 bg-white"
                }`}
              >
                {work.previewUrl ? (
                  <Image
                    src={work.previewUrl}
                    alt=""
                    width={56}
                    height={56}
                    unoptimized
                    className="h-14 w-14 shrink-0 rounded-md object-cover"
                  />
                ) : (
                  <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-[10px] text-neutral-400">
                    Kein Bild
                  </span>
                )}
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-sm font-medium text-neutral-900">{work.title}</span>
                  {work.composerName && <span className="block truncate text-xs text-neutral-500">{work.composerName}</span>}
                  <span className="mt-1 block text-xs font-medium text-[#0071e3]">
                    {work.imageCount} {work.imageCount === 1 ? "Bild" : "Bilder"} · Bearbeiten
                  </span>
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
