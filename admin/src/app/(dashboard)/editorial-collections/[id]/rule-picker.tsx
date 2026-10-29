"use client";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Sammlung automatisch
// befüllen. Person, Ensemble oder Spielstätte wählen → alle kommenden
// Konzerte damit landen in der Sammlung, neue kommen stündlich dazu.
// Manuelles Hinzufügen bleibt daneben möglich.

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { addCollectionRule, removeCollectionRule, searchCollectionRuleEntities, type RuleSearchResult } from "../actions";

export type CollectionRule = { entity_type: "person" | "ensemble" | "venue"; entity_id: string; label: string; upcoming: number };

const TYPE_LABEL: Record<CollectionRule["entity_type"], string> = { person: "Person", ensemble: "Ensemble", venue: "Spielstätte" };

export function RulePicker({ collectionId, rules }: { collectionId: string; rules: CollectionRule[] }) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<RuleSearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const active = new Set(rules.map((rule) => `${rule.entity_type}:${rule.entity_id}`));

  async function runSearch(value: string) {
    setQuery(value);
    if (value.trim().length < 2) {
      setResults([]);
      return;
    }
    setSearching(true);
    const found = await searchCollectionRuleEntities(value);
    setSearching(false);
    setResults(found);
  }

  function add(result: RuleSearchResult) {
    setError(null);
    setMessage(null);
    startTransition(async () => {
      try {
        const { added } = await addCollectionRule(collectionId, result.entity_type, result.entity_id);
        setMessage(`${result.label}: ${added} ${added === 1 ? "Konzert" : "Konzerte"} hinzugefügt.`);
        setQuery("");
        setResults([]);
        router.refresh();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Regel konnte nicht angelegt werden.");
      }
    });
  }

  function remove(rule: CollectionRule) {
    setError(null);
    setMessage(null);
    startTransition(async () => {
      try {
        await removeCollectionRule(collectionId, rule.entity_type, rule.entity_id);
        setMessage(`${rule.label} entfernt; kommende automatisch hinzugefügte Konzerte sind wieder raus.`);
        router.refresh();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Regel konnte nicht entfernt werden.");
      }
    });
  }

  return (
    <div className="max-w-xl">
      <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">Automatisch befüllen</p>
      <p className="mt-1 text-sm text-neutral-500">
        Alle kommenden Konzerte mit einer Person, einem Ensemble oder an einer Spielstätte landen automatisch in dieser Sammlung. Neue Termine kommen
        stündlich dazu. Einzelne automatisch hinzugefügte Konzerte lassen sich unten entfernen und kommen dann nicht wieder.
      </p>

      {rules.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-2">
          {rules.map((rule) => (
            <span key={`${rule.entity_type}:${rule.entity_id}`} className="inline-flex items-center gap-2 rounded-full bg-[#2D2A6E]/10 py-1 pl-3 pr-1.5 text-sm text-[#2D2A6E]">
              <span>
                <span className="text-xs opacity-70">{TYPE_LABEL[rule.entity_type]}:</span> {rule.label}
                <span className="ml-1 text-xs opacity-70">({rule.upcoming} kommend)</span>
              </span>
              <button
                type="button"
                disabled={pending}
                onClick={() => remove(rule)}
                aria-label={`Regel ${rule.label} entfernen`}
                className="flex size-5 items-center justify-center rounded-full hover:bg-[#2D2A6E]/15 disabled:opacity-50"
              >
                ×
              </button>
            </span>
          ))}
        </div>
      )}

      <input
        value={query}
        onChange={(event) => runSearch(event.target.value)}
        placeholder="z. B. Simon Rattle, BR-Symphonieorchester, Isarphilharmonie …"
        className="mt-3 w-full rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
      />
      {searching && <p className="mt-2 text-xs text-neutral-400">Suche…</p>}
      {results.length > 0 && (
        <div className="mt-2 flex flex-col rounded-md border border-neutral-200 bg-white">
          {results.map((result) => {
            const key = `${result.entity_type}:${result.entity_id}`;
            return (
              <div key={key} className="flex items-center justify-between gap-3 border-b border-neutral-100 px-3 py-2 text-sm last:border-b-0">
                <span className="min-w-0">
                  <span className="mr-2 rounded bg-neutral-100 px-1.5 py-0.5 text-[11px] text-neutral-600">{TYPE_LABEL[result.entity_type]}</span>
                  {result.label}
                  <span className="text-neutral-400">
                    {result.detail ? ` · ${result.detail}` : ""} · {result.upcoming} kommend
                  </span>
                </span>
                <button
                  type="button"
                  disabled={pending || active.has(key)}
                  onClick={() => add(result)}
                  className="shrink-0 text-xs font-medium text-[#2D2A6E] hover:underline disabled:opacity-40"
                >
                  {active.has(key) ? "Bereits aktiv" : "Alle Konzerte aufnehmen"}
                </button>
              </div>
            );
          })}
        </div>
      )}
      {message && <p className="mt-2 text-xs text-emerald-700">{message}</p>}
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
    </div>
  );
}
