"use client";

export default function EntityEditSuggestionsError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="p-8">
      <div className="max-w-xl rounded-2xl border border-amber-200 bg-amber-50 p-6">
        <h1 className="text-lg font-semibold text-[#18181B]">Profiländerungsvorschläge konnten nicht geladen werden</h1>
        <p className="mt-2 text-sm leading-6 text-[#52525B]">
          Bitte lade die Seite erneut. Es wurden keine Vorschläge verändert oder gelöscht.
        </p>
        <button type="button" onClick={reset} className="mt-4 rounded-full bg-[#2D2A6E] px-4 py-2 text-sm font-semibold text-white">
          Erneut versuchen
        </button>
      </div>
    </div>
  );
}
