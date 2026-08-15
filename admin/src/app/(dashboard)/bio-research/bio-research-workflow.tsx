"use client";

// Sequentieller Ablauf: EIN Eintrag nach dem anderen, KI-Recherche wird
// automatisch angestoßen, Ergebnis ist vor dem Übernehmen im Textfeld frei
// bearbeitbar — Nutzeranfrage: "mit KI nach einer Bio suchen und diese
// dann nacheinander (mit Option auf Bearbeitung) hinzufügen". Bewusst kein
// automatisches Speichern ohne Blick der Redaktion: ein biografischer
// Fließtext kann falsch/veraltet sein, selbst wenn die KI "confident"
// zurückgibt (siehe _shared/bioResearch.ts).
//
// BioStep ist eine eigene Komponente statt Recherche-State im Parent zu
// verwalten: mit key={current.id + retryKey} pro Eintrag/Retry neu
// gemountet, sodass der Recherche-Fetch ganz normal "on mount" im Effect
// passiert, statt den Zustand bei jedem Index-Wechsel manuell
// zurückzusetzen (das synchrone setState direkt im Effect-Body wäre sonst
// ein Lint-Fehler, siehe react-hooks/set-state-in-effect).

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { researchBio, saveBio, type BioEntityType, type BioResearchOutcome } from "./actions";

export interface BioWorkflowEntity {
  id: string;
  name: string;
  currentBio: string | null;
}

type StepState =
  | { status: "loading" }
  | { status: "found"; sourceUrl?: string; source?: "wikipedia" | "ai_knowledge" }
  | { status: "not_found" }
  | { status: "error"; message: string };

export function BioResearchWorkflow({
  entityType,
  entities,
}: {
  entityType: BioEntityType;
  entities: BioWorkflowEntity[];
}) {
  const [index, setIndex] = useState(0);
  const [results, setResults] = useState<{ saved: number; skipped: number }>({ saved: 0, skipped: 0 });

  // Nutzeranfrage: "die bio recherche in wikipedia dauert etwas zu lange"
  // — der eigentliche Wikipedia-Abruf ist bereits ein einzelner schlanker
  // API-Call (siehe _shared/wikipedia.ts), der spürbare Teil der Wartezeit
  // ist die anschließende KI-Zusammenfassung. Statt das serverseitig weiter
  // zu optimieren, wird hier die WARTEZEIT VERSTECKT: während die Redaktion
  // den aktuellen Eintrag liest/bearbeitet, läuft die Recherche für den
  // NÄCHSTEN Eintrag schon im Hintergrund — ein Cache aus in-flight
  // Promises statt eines einfachen Ergebnis-Caches, damit ein Prefetch, der
  // noch läuft, wenn man weiterklickt, nicht doppelt gestartet wird.
  const fetchCache = useRef<Map<string, Promise<BioResearchOutcome>>>(new Map());
  function ensureFetch(id: string) {
    let promise = fetchCache.current.get(id);
    if (!promise) {
      promise = researchBio(entityType, id);
      fetchCache.current.set(id, promise);
    }
    return promise;
  }
  // Für "Erneut recherchieren" — sonst würde ensureFetch das gecachte (evtl.
  // fehlgeschlagene) Ergebnis erneut zurückgeben, statt tatsächlich neu zu
  // fragen.
  function invalidateFetch(id: string) {
    fetchCache.current.delete(id);
  }

  const current = entities[index];
  const done = index >= entities.length;

  useEffect(() => {
    const next = entities[index + 1];
    if (next) ensureFetch(next.id);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- ensureFetch liest nur aus dem Ref, kein State-Zugriff
  }, [index, entities]);

  function advance(outcome: "saved" | "skipped") {
    setResults((prev) => ({ ...prev, [outcome]: prev[outcome] + 1 }));
    setIndex((i) => i + 1);
  }

  if (done) {
    return (
      <div className="rounded-xl border border-black/[0.06] bg-white p-6 shadow-sm">
        <p className="text-sm font-medium text-neutral-900">
          Fertig — {results.saved} übernommen, {results.skipped} übersprungen von {entities.length}.
        </p>
        <Link
          href={entityType === "person" ? "/persons" : entityType === "ensemble" ? "/ensembles" : "/venues"}
          className="mt-4 inline-block rounded-lg bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
        >
          Zurück zur Liste
        </Link>
      </div>
    );
  }

  return (
    <div className="max-w-2xl">
      <div className="flex items-center justify-between">
        <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">
          {index + 1} / {entities.length}
        </p>
        <p className="text-xs text-neutral-400">
          {results.saved + results.skipped} erledigt
        </p>
      </div>
      {/* Sichtbarer Fortschrittsbalken statt nur des "N / M"-Texts —
          Nutzeranfrage: "außerdem muss man einen Fortschritt sehen". */}
      <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-neutral-100">
        <div
          className="h-full rounded-full bg-neutral-900 transition-all duration-300"
          style={{ width: `${(index / entities.length) * 100}%` }}
        />
      </div>
      <BioStep
        key={current.id}
        entityType={entityType}
        entity={current}
        ensureFetch={ensureFetch}
        invalidateFetch={invalidateFetch}
        onTakeOver={() => advance("saved")}
        onSkip={() => advance("skipped")}
      />
    </div>
  );
}

function BioStep({
  entityType,
  entity,
  ensureFetch,
  invalidateFetch,
  onTakeOver,
  onSkip,
}: {
  entityType: BioEntityType;
  entity: BioWorkflowEntity;
  ensureFetch: (id: string) => Promise<BioResearchOutcome>;
  invalidateFetch: (id: string) => void;
  onTakeOver: () => void;
  onSkip: () => void;
}) {
  const [retryKey, setRetryKey] = useState(0);
  const [step, setStep] = useState<StepState>({ status: "loading" });
  const [draft, setDraft] = useState(entity.currentBio ?? "");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;

    ensureFetch(entity.id).then((result) => {
      if (cancelled) return;
      if (result.error) {
        setStep({ status: "error", message: result.error });
      } else if (result.found && result.biography) {
        setStep({ status: "found", sourceUrl: result.sourceUrl, source: result.source });
        setDraft(result.biography);
      } else {
        setStep({ status: "not_found" });
      }
    });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- retryKey erzwingt bewusst einen Re-Fetch, ensureFetch selbst ist stabil (aus dem Parent-Ref)
  }, [entity.id, retryKey]);

  async function handleTakeOver() {
    setSaving(true);
    try {
      await saveBio(entityType, entity.id, draft);
      onTakeOver();
    } catch (err) {
      setStep({ status: "error", message: err instanceof Error ? err.message : "Speichern fehlgeschlagen." });
    } finally {
      setSaving(false);
    }
  }

  return (
    <div>
      <h2 className="mt-1 text-lg font-semibold text-neutral-900">{entity.name}</h2>

      {entity.currentBio && (
        <div className="mt-3 border border-neutral-300 bg-neutral-50 p-3 text-xs text-neutral-500">
          <p className="font-medium uppercase tracking-wide">Bisherige Bio</p>
          <p className="mt-1">{entity.currentBio}</p>
        </div>
      )}

      <div className="mt-4">
        {step.status === "loading" && (
          <p className="text-sm text-neutral-500">KI erstellt die Biografie direkt aus ihrem Wissen…</p>
        )}

        {step.status === "not_found" && (
          <p className="text-sm text-amber-700">
            Weder aus KI-Wissen noch im Quellen-Fallback etwas Verlässliches gefunden — Text unten manuell eintragen oder
            überspringen.
          </p>
        )}

        {step.status === "error" && <p className="text-sm text-red-600">Fehler: {step.message}</p>}

        {step.status === "found" && step.source === "wikipedia" && step.sourceUrl && (
          <p className="text-xs text-neutral-500">
            Quelle:{" "}
            <a href={step.sourceUrl} target="_blank" rel="noreferrer" className="text-blue-600 hover:underline">
              {step.sourceUrl}
            </a>
          </p>
        )}

        {step.status === "found" && step.source === "ai_knowledge" && (
          <p className="rounded bg-amber-50 px-2 py-1 text-xs text-amber-800">
            KI-Entwurf aus eigenem Wissen ohne langsamen Webabruf. Vor der Übernahme frei bearbeiten und inhaltlich prüfen.
          </p>
        )}

        <textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          rows={8}
          placeholder="Noch kein Text — recherchiert oder manuell eintragen."
          className="mt-2 w-full rounded-lg border border-black/10 p-3 text-sm outline-none focus:border-[#0071e3]"
        />

        <div className="mt-3 flex items-center gap-3">
          <button
            type="button"
            disabled={saving || !draft.trim()}
            onClick={handleTakeOver}
            className="rounded-lg bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
          >
            {saving ? "Speichere…" : "Übernehmen & weiter"}
          </button>
          <button
            type="button"
            disabled={saving}
            onClick={onSkip}
            className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
          >
            Überspringen
          </button>
          <button
            type="button"
            disabled={saving || step.status === "loading"}
            onClick={() => {
              invalidateFetch(entity.id);
              setStep({ status: "loading" });
              setRetryKey((k) => k + 1);
            }}
            className="text-sm font-medium text-neutral-500 hover:text-neutral-800 disabled:opacity-50"
          >
            Erneut recherchieren
          </button>
        </div>
      </div>
    </div>
  );
}
