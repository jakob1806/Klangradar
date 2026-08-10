"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { probeSource } from "./actions";
import { INITIAL_STATE } from "./types";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
    >
      {pending ? "Teste… (kann bis zu einer Minute dauern)" : "Testen"}
    </button>
  );
}

export default function OnboardSourcePage() {
  const [state, formAction] = useActionState(probeSource, INITIAL_STATE);

  return (
    <div className="p-8">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Neue Quelle testen</h1>
          <p className="max-w-xl text-sm text-neutral-500">
            URL eingeben — das System probiert automatisch Schema.org, RSS/iCal und zuletzt eine KI-Vorschau durch
            und zeigt, was erkannt wurde, bevor irgendetwas angelegt wird.
          </p>
        </div>
        <Link href="/sources" className="text-sm font-medium text-neutral-700 hover:text-neutral-900">
          Zurück zu Datenquellen
        </Link>
      </div>

      <form action={formAction} className="max-w-2xl rounded-lg border border-neutral-200 bg-white p-6">
        <label htmlFor="url" className="block text-sm font-medium text-neutral-900">
          URL
        </label>
        <input
          id="url"
          name="url"
          type="url"
          required
          placeholder="https://…"
          className="mt-2 w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-500 focus:outline-none"
        />
        <div className="mt-4">
          <SubmitButton />
        </div>
      </form>

      {state.status === "ok" && (
        <div className="mt-6 max-w-2xl rounded-lg border border-emerald-200 bg-emerald-50 p-6">
          <p className="text-sm font-medium text-emerald-900">
            {state.eventsFound} Veranstaltung(en) erkannt über{" "}
            <span className="font-mono">{state.recommendedType}</span> — vollautomatisch, keine Konfiguration nötig.
          </p>
          <PreviewList items={state.preview} />
          <Link
            href={`/sources/new?url=${encodeURIComponent(state.url ?? "")}&type=${state.recommendedType}`}
            className="mt-4 inline-block rounded-md bg-emerald-700 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-800"
          >
            Diese Quelle anlegen →
          </Link>
        </div>
      )}

      {state.status === "ok_manual_only" && (
        <div className="mt-6 max-w-2xl rounded-lg border border-amber-200 bg-amber-50 p-6">
          <p className="text-sm font-medium text-amber-900">
            {state.eventsFound} Veranstaltung(en) per KI im Seitentext erkannt — aber keine strukturierten Daten.
          </p>
          <p className="mt-2 text-sm text-amber-800">{state.message}</p>
          <PreviewList items={state.preview} />
          <div className="mt-4 flex gap-3">
            <Link
              href="/events/from-url"
              className="rounded-md bg-amber-700 px-4 py-2 text-sm font-medium text-white hover:bg-amber-800"
            >
              Events einzeln importieren →
            </Link>
            <Link
              href={`/sources/new?url=${encodeURIComponent(state.url ?? "")}&type=scrape`}
              className="rounded-md border border-amber-300 px-4 py-2 text-sm font-medium text-amber-900 hover:bg-amber-100"
            >
              Trotzdem als scrape-Quelle anlegen (braucht CSS-Selektoren)
            </Link>
          </div>
        </div>
      )}

      {(state.status === "no_events_found" || state.status === "blocked" || state.status === "failed") && (
        <div className="mt-6 max-w-2xl rounded-lg border border-red-200 bg-red-50 p-6">
          <p className="text-sm font-medium text-red-900">{state.error ?? state.message}</p>
          {state.errors && state.errors.length > 0 && (
            <ul className="mt-2 list-disc space-y-1 pl-4 text-sm text-red-800">
              {state.errors.map((e, i) => (
                <li key={i}>{e}</li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

function PreviewList({ items }: { items?: { title: string; startDateTime: string; venueName: string | null }[] }) {
  if (!items || items.length === 0) return null;
  return (
    <ul className="mt-3 space-y-1 text-sm text-neutral-700">
      {items.map((e, i) => (
        <li key={i}>
          {e.title} — {new Date(e.startDateTime).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" })}
          {e.venueName ? ` · ${e.venueName}` : ""}
        </li>
      ))}
    </ul>
  );
}
