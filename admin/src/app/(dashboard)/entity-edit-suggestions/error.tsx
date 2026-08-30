"use client";

export default function EntityEditSuggestionsError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="p-8">
      <div className="max-w-xl rounded-2xl border border-amber-200 bg-amber-50 p-6">
        <h1 className="text-lg font-semibold text-[#1d1d1f]">Profiländerungsvorschläge konnten nicht geladen werden</h1>
        <p className="mt-2 text-sm leading-6 text-[#48484a]">
          Bitte lade die Seite erneut. Es wurden keine Vorschläge verändert oder gelöscht.
        </p>
        <button type="button" onClick={reset} className="mt-4 rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white">
          Erneut versuchen
        </button>
      </div>
    </div>
  );
}
