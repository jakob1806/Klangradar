"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import Image from "next/image";
import { searchClaimCandidates, type ClaimMatch, type ClaimMatchType } from "./search-actions";
import { requestOrganizerClaim } from "./actions";
import { requestEntityClaim } from "./entity-claim-actions";
import { SubmitButton } from "@/components/organizer/submit-button";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/organizer/ui/card";
import { Input, Textarea } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { cn } from "@/lib/utils";

const TYPE_LABEL: Record<ClaimMatchType, string> = {
  organizer: "Institution",
  venue: "Venue",
  person: "Person",
  ensemble: "Ensemble",
};

function Thumbnail({ match }: { match: ClaimMatch }) {
  const rounded = match.type === "person";
  if (!match.photoUrl) {
    return (
      <div
        className={cn(
          "flex size-10 shrink-0 items-center justify-center bg-[#ECEBFA] text-[13px] font-semibold text-[#2D2A6E]",
          rounded ? "rounded-full" : "rounded-lg"
        )}
      >
        {match.name.charAt(0).toUpperCase()}
      </div>
    );
  }
  return (
    <Image
      src={match.photoUrl}
      alt=""
      width={40}
      height={40}
      unoptimized
      className={cn("size-10 shrink-0 object-cover", rounded ? "rounded-full" : "rounded-lg")}
    />
  );
}

// Nutzerfeedback: "man soll nicht erst auf Suchen klicken müssen" — Live-
// Vorschläge samt Miniaturbild (Venue/Ensemble eckig, Person rund) statt
// der bisherigen GET-Suche. Debounce statt Suche pro Tastenanschlag, um
// die vier find_matching_*-RPCs nicht bei jedem Buchstaben parallel zu
// feuern.
export function ClaimSearch() {
  const [query, setQuery] = useState("");
  const [matches, setMatches] = useState<ClaimMatch[]>([]);
  const [selected, setSelected] = useState<ClaimMatch | null>(null);
  const [isPending, startTransition] = useTransition();
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    // Bei zu kurzer Eingabe oder frisch getroffener Auswahl wird bewusst
    // nichts zurückgesetzt: die Vorschlagsliste unten blendet sich ohnehin
    // aus (siehe `query.trim().length >= 2` im Render), ein setState hier
    // wäre nur ein Cascading-Render ohne sichtbaren Effekt (react-hooks/
    // set-state-in-effect).
    if (selected || query.trim().length < 2) return;
    debounceRef.current = setTimeout(() => {
      startTransition(async () => {
        setMatches(await searchClaimCandidates(query));
      });
    }, 250);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [query, selected]);

  return (
    <div className="flex flex-col gap-4">
      <div className="relative">
        <Input
          type="search"
          value={query}
          onChange={(e) => {
            setSelected(null);
            setQuery(e.target.value);
          }}
          placeholder="Name suchen…"
          autoComplete="off"
        />
        {!selected && query.trim().length >= 2 && (
          <div className="absolute inset-x-0 top-full z-10 mt-1 max-h-80 overflow-y-auto rounded-lg border border-black/10 bg-white shadow-lg">
            {isPending && matches.length === 0 ? (
              <p className="px-3 py-3 text-sm text-[#726c78]">Suche…</p>
            ) : matches.length === 0 ? (
              <p className="px-3 py-3 text-sm text-[#726c78]">Keine Treffer für „{query}“.</p>
            ) : (
              matches.map((m) => (
                <button
                  key={`${m.type}-${m.id}`}
                  type="button"
                  onClick={() => {
                    setSelected(m);
                    setQuery(m.name);
                  }}
                  className="flex w-full items-center gap-3 px-3 py-2 text-left transition hover:bg-[#F5F5F1]"
                >
                  <Thumbnail match={m} />
                  <span className="flex flex-col">
                    <span className="text-sm font-medium text-[#15131a]">{m.name}</span>
                    <span className="text-[11px] font-semibold uppercase tracking-[0.04em] text-[#A1A1AA]">{TYPE_LABEL[m.type]}</span>
                  </span>
                </button>
              ))
            )}
          </div>
        )}
      </div>

      {selected && (
        <Card>
          <CardHeader>
            <div className="flex items-center gap-3">
              <Thumbnail match={selected} />
              <div>
                <span className="mb-1 block rounded-full bg-[#ECEBFA] px-2 py-0.5 text-[11px] font-semibold uppercase tracking-[0.04em] text-[#2D2A6E] w-fit">
                  {TYPE_LABEL[selected.type]}
                </span>
                <CardTitle>{selected.name}</CardTitle>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <form
              action={
                selected.type === "organizer"
                  ? requestOrganizerClaim.bind(null, selected.id)
                  : requestEntityClaim.bind(null, selected.type, selected.id)
              }
              className="grid gap-3 sm:grid-cols-2"
            >
              <div className="flex flex-col gap-1.5">
                <Label>
                  Geschäftliche E-Mail <span className="text-[#a91551]">*</span>
                </Label>
                <Input name="verification_email" type="email" required placeholder="name@institution.de" />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>
                  Nachweis-Link <span className="text-[#a91551]">*</span>
                </Label>
                <Input name="evidence_url" type="url" required placeholder="https://www.beispiel.de/impressum" />
              </div>
              <div className="flex flex-col gap-1.5 sm:col-span-2">
                <Label>
                  Warum bist du berechtigt? <span className="text-[#a91551]">*</span>
                </Label>
                <Textarea name="justification" rows={2} required placeholder="Funktion bei der Institution und Bezug zum Nachweis" />
              </div>
              <div className="sm:col-span-2">
                <SubmitButton pendingLabel="Sende…">Mit Nachweis beantragen</SubmitButton>
              </div>
            </form>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
