"use client";

// Pendant zu bio-research-workflow.tsx, nur für Bilder — Nutzeranfrage:
// "das gleiche möchte ich auch bei Bildern haben, man soll alle Personen,
// Venues, Ensembles oder Veranstaltungen auswählen können, dann schritt
// für schritt ein Bild dafür recherchieren von KI lassen. auch möglich
// ist, dass man dann jeweils einen Link dazu schickt... auch soll der
// Admin selber bis zu mehrere Bilder hinzufügen können."
//
// Zwei Phasen in EINER Komponente (kein Seitenwechsel/keine IDs in der
// URL, die bei vielen Auswahlen zu lang würde): erst Auswahl (Checkboxen +
// Namensfilter + "nur ohne Bild"), dann Schritt-für-Schritt-Recherche.

import { useEffect, useRef, useState } from "react";
import {
  searchEntityImage,
  commitEntityImage,
  commitManualImage,
  type ImageEntityType,
  type ImageSearchResult,
} from "./actions";

export interface ImageEntityOption {
  id: string;
  name: string;
  hasImage: boolean;
}

export function ImageResearchClient({
  entityType,
  entities,
}: {
  entityType: ImageEntityType;
  entities: ImageEntityOption[];
}) {
  const [phase, setPhase] = useState<"select" | "workflow">("select");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [filter, setFilter] = useState("");
  const [onlyMissing, setOnlyMissing] = useState(false);

  const visible = entities.filter((e) => {
    if (onlyMissing && e.hasImage) return false;
    if (filter && !e.name.toLowerCase().includes(filter.toLowerCase())) return false;
    return true;
  });

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  if (phase === "workflow") {
    const chosen = entities.filter((e) => selected.has(e.id));
    return (
      <ImageWorkflow
        entityType={entityType}
        entities={chosen}
        onBack={() => setPhase("select")}
      />
    );
  }

  return (
    <div>
      {/* Nutzerfeedback: der Recherche-Button saß bisher UNTER der ganzen
          (bis zu 500 Einträge langen) Liste — man musste immer erst ganz
          runterscrollen. Jetzt oben neben den Auswahl-Controls, bleibt
          sichtbar ohne die Liste scrollen zu müssen. */}
      <div className="flex flex-wrap items-center gap-3">
        <input
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Name filtern…"
          className="rounded-lg border border-black/10 px-3 py-1.5 text-sm outline-none focus:border-[#0071e3]"
        />
        <label className="flex items-center gap-1.5 text-sm text-neutral-600">
          <input
            type="checkbox"
            checked={onlyMissing}
            onChange={(e) => setOnlyMissing(e.target.checked)}
            className="h-4 w-4 rounded border-neutral-300"
          />
          Nur ohne Bild
        </label>
        <button
          type="button"
          onClick={() => setSelected(new Set(visible.map((e) => e.id)))}
          className="text-xs font-medium text-neutral-500 underline hover:text-neutral-800"
        >
          Alle sichtbaren auswählen ({visible.length})
        </button>
        {selected.size > 0 && (
          <button
            type="button"
            onClick={() => setSelected(new Set())}
            className="text-xs font-medium text-neutral-500 underline hover:text-neutral-800"
          >
            Auswahl leeren
          </button>
        )}
        {selected.size > 0 && (
          <button
            type="button"
            onClick={() => setPhase("workflow")}
            className="ml-auto rounded-full bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
          >
            {selected.size} ausgewählt — Bilder recherchieren →
          </button>
        )}
      </div>

      <div className="mt-4 max-h-[60vh] overflow-y-auto rounded-xl border border-black/[0.06] bg-white shadow-sm">
        {visible.map((e) => (
          <label
            key={e.id}
            className="flex items-center gap-3 border-b border-neutral-100 px-4 py-2.5 text-sm last:border-b-0 hover:bg-neutral-50"
          >
            <input
              type="checkbox"
              checked={selected.has(e.id)}
              onChange={() => toggle(e.id)}
              className="h-4 w-4 rounded border-neutral-300"
            />
            <span className="flex-1 text-neutral-900">{e.name}</span>
            <span
              className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${
                e.hasImage ? "bg-blue-50 text-blue-700" : "bg-neutral-100 text-neutral-400"
              }`}
            >
              {e.hasImage ? "Bild vorhanden" : "Kein Bild"}
            </span>
          </label>
        ))}
        {visible.length === 0 && <p className="px-4 py-6 text-sm text-neutral-400">Keine Treffer.</p>}
      </div>
    </div>
  );
}

const LICENSE_LABEL: Record<"confirmed_free" | "confirmed_licensed", string> = {
  confirmed_free: "Frei nutzbar",
  confirmed_licensed: "Lizenziert (mit Quellenangabe)",
};

function ImageWorkflow({
  entityType,
  entities,
  onBack,
}: {
  entityType: ImageEntityType;
  entities: ImageEntityOption[];
  onBack: () => void;
}) {
  const [index, setIndex] = useState(0);
  const [results, setResults] = useState({ saved: 0, skipped: 0 });
  const current = entities[index];
  const done = index >= entities.length;

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
        <button
          type="button"
          onClick={onBack}
          className="mt-4 rounded-full bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed]"
        >
          Zurück zur Auswahl
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-xl">
      <div className="flex items-center justify-between">
        <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">
          {index + 1} / {entities.length}
        </p>
        <p className="text-xs text-neutral-400">{results.saved + results.skipped} erledigt</p>
      </div>
      <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-neutral-100">
        <div
          className="h-full rounded-full bg-neutral-900 transition-all duration-300"
          style={{ width: `${(index / entities.length) * 100}%` }}
        />
      </div>
      <ImageStep
        key={current.id}
        entityType={entityType}
        entity={current}
        onTakeOver={() => advance("saved")}
        onSkip={() => advance("skipped")}
      />
    </div>
  );
}

type StepState =
  | { status: "loading" }
  | { status: "found"; result: ImageSearchResult }
  | { status: "not_found"; error?: string }
  | { status: "idle" };

function ImageStep({
  entityType,
  entity,
  onTakeOver,
  onSkip,
}: {
  entityType: ImageEntityType;
  entity: ImageEntityOption;
  onTakeOver: () => void;
  onSkip: () => void;
}) {
  const [step, setStep] = useState<StepState>({ status: "loading" });
  const [urlInput, setUrlInput] = useState("");
  const [activeUrl, setActiveUrl] = useState<string | undefined>(undefined);
  const [retryKey, setRetryKey] = useState(0);
  const [licenseStatus, setLicenseStatus] = useState<"confirmed_free" | "confirmed_licensed">("confirmed_licensed");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Der Fetch selbst läuft NUR im Effect, ausgelöst über die Dependencies
  // (entity.id/activeUrl/retryKey) — setState passiert ausschließlich im
  // .then()-Callback, nie synchron im Effect-Body (react-hooks: "Calling
  // setState synchronously within an effect"). Den "loading"-Zustand
  // setzen die AUSLÖSENDEN Stellen selbst (Button-Klick/State-Änderung),
  // nicht der Effect — analog zu bio-research-workflow.tsx.
  useEffect(() => {
    let cancelled = false;
    searchEntityImage(entityType, entity.id, activeUrl).then((result) => {
      if (cancelled) return;
      if (result.found) {
        setStep({ status: "found", result });
        setLicenseStatus(result.suggestedLicenseStatus ?? "confirmed_licensed");
      } else {
        setStep({ status: "not_found", error: result.error });
      }
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- entityType ist über die Lebensdauer der Komponente konstant
  }, [entity.id, activeUrl, retryKey]);

  function runSearch(sourceUrl?: string) {
    setStep({ status: "loading" });
    setError(null);
    if (sourceUrl === activeUrl) {
      // Effect-Dependency ändert sich nicht (gleicher Wert) — retryKey
      // erzwingt trotzdem einen erneuten Lauf (z.B. "Erneut recherchieren"
      // ohne Link-Änderung).
      setRetryKey((k) => k + 1);
    } else {
      setActiveUrl(sourceUrl);
    }
  }

  async function handleTakeOver() {
    if (step.status !== "found") return;
    setBusy(true);
    setError(null);
    const res = await commitEntityImage(entityType, entity.id, {
      sourceUrl: step.result.imageUrl,
      sourceName: step.result.sourceName,
      sourcePageUrl: step.result.sourcePageUrl,
      matchReason: step.result.matchReason,
      licenseStatus,
    });
    setBusy(false);
    if (res.committed) onTakeOver();
    else setError(res.error ?? "Übernehmen fehlgeschlagen.");
  }

  async function handleUploadSelected() {
    if (selectedFiles.length === 0) return;
    setBusy(true);
    setError(null);
    let anySuccess = false;
    for (const file of selectedFiles) {
      const base64 = await fileToBase64(file);
      const res = await commitManualImage(entityType, entity.id, base64, licenseStatus);
      if (res.committed) anySuccess = true;
      else setError(res.error ?? `Upload von "${file.name}" fehlgeschlagen.`);
    }
    setBusy(false);
    setSelectedFiles([]);
    if (fileInputRef.current) fileInputRef.current.value = "";
    if (anySuccess) onTakeOver();
  }

  return (
    <div>
      <h2 className="mt-1 text-lg font-semibold text-neutral-900">{entity.name}</h2>

      <div className="mt-4">
        {step.status === "loading" && <p className="text-sm text-neutral-500">KI recherchiert…</p>}

        {step.status === "not_found" && (
          <p className="text-sm text-amber-700">
            {step.error ?? "Nichts gefunden."} — Link unten angeben oder Datei hochladen.
          </p>
        )}

        {step.status === "found" && (
          <div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={
                step.result.imagePreviewBase64
                  ? `data:${step.result.imagePreviewMimeType ?? "image/jpeg"};base64,${step.result.imagePreviewBase64}`
                  : step.result.imageUrl
              }
              alt=""
              className="max-h-64 w-full border border-neutral-300 object-contain bg-neutral-50"
            />
            <p className="mt-2 text-xs text-neutral-500">
              Quelle: {step.result.sourceName ?? "unbekannt"}
              {step.result.matchReason ? ` · ${step.result.matchReason}` : ""}
            </p>
            {step.result.sourcePageUrl && (
              <a
                href={step.result.sourcePageUrl}
                target="_blank"
                rel="noreferrer"
                className="mt-1 block truncate text-xs text-blue-600 hover:underline"
              >
                {step.result.sourcePageUrl}
              </a>
            )}
            <div className="mt-3 flex items-center gap-4 text-xs">
              {(["confirmed_free", "confirmed_licensed"] as const).map((v) => (
                <label key={v} className="flex items-center gap-1.5">
                  <input
                    type="radio"
                    checked={licenseStatus === v}
                    onChange={() => setLicenseStatus(v)}
                    className="h-3.5 w-3.5"
                  />
                  {LICENSE_LABEL[v]}
                </label>
              ))}
            </div>
            <button
              type="button"
              disabled={busy}
              onClick={handleTakeOver}
              className="mt-3 rounded-full bg-[#0071e3] px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
            >
              {busy ? "Speichere…" : "Übernehmen & weiter"}
            </button>
          </div>
        )}

        {error && <p className="mt-2 text-sm text-red-600">{error}</p>}

        <div className="mt-4 border-t border-neutral-100 pt-4">
          <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">Oder: Link angeben</p>
          <div className="mt-2 flex gap-2">
            <input
              value={urlInput}
              onChange={(e) => setUrlInput(e.target.value)}
              placeholder="https://…"
              className="flex-1 rounded-lg border border-black/10 px-3 py-1.5 text-sm outline-none focus:border-[#0071e3]"
            />
            <button
              type="button"
              disabled={!urlInput.trim() || busy}
              onClick={() => runSearch(urlInput.trim())}
              className="rounded-lg border border-black/10 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-black/[0.04] disabled:opacity-50"
            >
              Bild von Link holen
            </button>
          </div>
        </div>

        <div className="mt-4 border-t border-neutral-100 pt-4">
          <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">
            Oder: eigene Datei(en) hochladen
          </p>
          {/* Nutzerfeedback: "für eigene datei hochladen fehlt noch ein
              richtiger button" — der native <input type=file> allein sieht
              je nach Browser nicht wie ein anklickbarer Button aus.
              Auswahl und Upload jetzt getrennt: erst Dateien wählen (Namen
              werden gelistet, abwählbar), dann EIN expliziter "Hochladen"-
              Button löst den eigentlichen Upload aus. */}
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            multiple
            disabled={busy}
            onChange={(e) => setSelectedFiles(Array.from(e.target.files ?? []))}
            className="hidden"
          />
          <div className="mt-2 flex items-center gap-2">
            <button
              type="button"
              disabled={busy}
              onClick={() => fileInputRef.current?.click()}
              className="rounded-lg border border-black/10 px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-black/[0.04] disabled:opacity-50"
            >
              Datei(en) auswählen…
            </button>
            {selectedFiles.length > 0 && (
              <button
                type="button"
                disabled={busy}
                onClick={handleUploadSelected}
                className="rounded-full bg-[#0071e3] px-4 py-1.5 text-sm font-medium text-white transition-colors hover:bg-[#0077ed] disabled:opacity-50"
              >
                {busy ? "Lade hoch…" : `${selectedFiles.length} Datei(en) hochladen`}
              </button>
            )}
          </div>
          {selectedFiles.length > 0 && (
            <ul className="mt-2 flex flex-col gap-1">
              {selectedFiles.map((file, i) => (
                <li key={`${file.name}-${i}`} className="flex items-center justify-between text-xs text-neutral-600">
                  <span className="truncate">{file.name}</span>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setSelectedFiles((prev) => prev.filter((_, idx) => idx !== i))}
                    className="ml-2 text-neutral-400 hover:text-red-600 disabled:opacity-50"
                  >
                    Entfernen
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="mt-4 flex items-center gap-3">
          <button
            type="button"
            disabled={busy}
            onClick={onSkip}
            className="text-sm font-medium text-neutral-600 hover:text-neutral-900 disabled:opacity-50"
          >
            Überspringen
          </button>
          <button
            type="button"
            disabled={busy || step.status === "loading"}
            onClick={() => runSearch()}
            className="text-sm font-medium text-neutral-500 hover:text-neutral-800 disabled:opacity-50"
          >
            Erneut recherchieren
          </button>
        </div>
      </div>
    </div>
  );
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      // "data:image/png;base64,AAAA..." -> nur der Teil nach dem Komma
      resolve(result.split(",")[1] ?? "");
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
