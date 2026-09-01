"use client";

import { useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Input } from "@/components/organizer/ui/input";

interface VenueMatch {
  id: string;
  name: string;
}

// Typeahead statt eines <select> mit ALLEN Venues (wie im Redaktions-
// Formular event-form.tsx) — für Selbstbedienung falsch skaliert, und ein
// Veranstalter soll ohnehin nur seine tatsächliche Spielstätte per Suche
// finden, nicht durch hunderte fremde Venues scrollen. Ruft find_matching_venue
// direkt vom Client aus auf (venues sind öffentlich lesbar per RLS, die RPC
// braucht keine erhöhten Rechte) statt über eine Server Action pro Tastendruck.
export function VenuePicker({
  initial,
  onSelect,
}: {
  initial?: VenueMatch;
  onSelect?: (venue: VenueMatch | null) => void;
}) {
  const [query, setQuery] = useState(initial?.name ?? "");
  const [selected, setSelected] = useState<VenueMatch | null>(initial ?? null);
  const [results, setResults] = useState<VenueMatch[]>([]);
  const [open, setOpen] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (selected && query === selected.name) return;
    const trimmed = query.trim();
    if (debounceRef.current) clearTimeout(debounceRef.current);
    // setResults([]) für den "zu kurz"-Fall bewusst auch im Timeout statt
    // synchron im Effekt-Body — sonst kaskadierende Renders direkt beim
    // Tastendruck (react-hooks/set-state-in-effect).
    debounceRef.current = setTimeout(async () => {
      if (trimmed.length < 2) {
        setResults([]);
        return;
      }
      const supabase = createClient();
      const { data } = await supabase.rpc("find_matching_venue", {
        p_name: trimmed,
        p_similarity_threshold: 0.2,
        p_result_limit: 8,
      });
      setResults(((data ?? []) as VenueMatch[]).map((r) => ({ id: r.id, name: r.name })));
      setOpen(true);
    }, 300);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  return (
    <div className="relative">
      <input type="hidden" name="venue_id" value={selected?.id ?? ""} required />
      <Input
        type="text"
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setSelected(null);
          onSelect?.(null);
        }}
        onFocus={() => results.length > 0 && setOpen(true)}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        placeholder="Venue suchen…"
      />
      {open && results.length > 0 && (
        <ul className="absolute z-10 mt-1 w-full overflow-hidden rounded-xl border border-[#15131a]/[0.08] bg-white shadow-lg">
          {results.map((venue) => (
            <li key={venue.id}>
              <button
                type="button"
                onClick={() => {
                  setSelected(venue);
                  setQuery(venue.name);
                  setOpen(false);
                  onSelect?.(venue);
                }}
                className="block w-full px-3 py-2 text-left text-sm text-[#15131a] hover:bg-[#2D2A6E]/[0.05]"
              >
                {venue.name}
              </button>
            </li>
          ))}
        </ul>
      )}
      {!selected && query.trim().length >= 2 && (
        <p className="mt-1 text-xs text-[#8a5a0c]">Bitte eine Venue aus der Liste auswählen.</p>
      )}
    </div>
  );
}
