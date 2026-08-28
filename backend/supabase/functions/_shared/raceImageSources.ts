// Nutzerwunsch: "Alle Quellen parallel statt in Kette abfragen und das
// beste Ergebnis nach Score wählen, statt beim ersten Treffer zu stoppen."
//
// Wichtige Einschränkung, die beim reinen "höchster Score gewinnt" verloren
// ginge: research-entity-image/index.ts (searchWithoutPreview) begründet
// explizit, warum bei Personen die offizielle Website VOR Wikipedia geprüft
// wird — "sonst wird ein formal vorhandenes, aber falsches Personenbild
// voreilig zurückgegeben" (Namensgleichheit). Eine offizielle Website ist
// identitäts-sicherer als ein Wikipedia-/Websuche-Treffer, auch wenn dessen
// Bild-Score (Auflösung, Schärfe, ...) höher ausfällt — ein reiner
// score-basierter Vergleich über ALLE Quellen hinweg würde genau den
// bereits live behobenen Fehler wieder einführen.
//
// Deshalb: gestaffeltes Rennen statt eines einzigen globalen Wettbewerbs.
// Jede Quelle bekommt eine `tier` (niedrigere Zahl = vertrauenswürdiger,
// z.B. offizielle Website=0, Wikipedia/Wikidata/Commons=1, freie Websuche=2).
// ALLE Quellen laufen parallel (echter Geschwindigkeitsgewinn — nicht mehr
// nacheinander warten), aber unter den gefundenen Kandidaten gewinnt immer
// die niedrigste Tier-Zahl, die überhaupt etwas geliefert hat; NUR
// innerhalb derselben Tier entscheidet der Score (z.B. DuckDuckGo vs.
// Gemini-Grounding innerhalb der Websuch-Tier — dort sind es tatsächlich
// gleichwertige Alternativen, kein Identitäts-Sicherheits-Unterschied).

export interface ImageSourceAttempt<T> {
  /** Für Logging/Debugging — z.B. "Offizielle Website", "Wikipedia". */
  source: string;
  /** Niedrigere Zahl = vertrauenswürdiger/identitätssicherer, siehe
   * Datei-Kommentar. Quellen mit gleicher Tier konkurrieren per Score. */
  tier: number;
  /** Liefert null bei "nichts gefunden" (kein Fehlerfall) oder wirft bei
   * einem echten Fehler — beides wird von raceImageSources() abgefangen,
   * ein einzelner Quellen-Fehlschlag darf die anderen nie blockieren. */
  run: () => Promise<{ candidate: T; score: number } | null>;
}

export type ImageSourceAttemptOutcome =
  | { source: string; tier: number; outcome: "found"; score: number }
  | { source: string; tier: number; outcome: "not_found" }
  | { source: string; tier: number; outcome: "error"; detail: string };

export interface RaceImageSourcesResult<T> {
  winner: { source: string; tier: number; candidate: T; score: number } | null;
  /** Ergebnis jeder einzelnen Quelle, unabhängig vom Gewinner — fürs
   * bestehende RunLogEntry-Logging (research-entity-image) bzw.
   * last_image_search_note (enrich-entity-images). */
  attempts: ImageSourceAttemptOutcome[];
}

/** Führt alle übergebenen Quellen parallel aus (Promise.allSettled — ein
 * einzelner Fehlschlag/Wurf blockiert die anderen nicht) und wählt den
 * Gewinner nach Tier-dann-Score, siehe Datei-Kommentar. Reine
 * Orchestrierung ohne eigene Netzwerklogik — testbar mit gemockten
 * `run()`-Funktionen, siehe raceImageSources.test.ts. */
export async function raceImageSources<T>(
  sources: ImageSourceAttempt<T>[],
): Promise<RaceImageSourcesResult<T>> {
  const settled = await Promise.allSettled(sources.map((s) => s.run()));

  const attempts: ImageSourceAttemptOutcome[] = [];
  const found: Array<{ source: string; tier: number; candidate: T; score: number }> = [];

  settled.forEach((result, i) => {
    const s = sources[i];
    if (result.status === "rejected") {
      attempts.push({
        source: s.source,
        tier: s.tier,
        outcome: "error",
        detail: result.reason instanceof Error ? result.reason.message : String(result.reason),
      });
      return;
    }
    if (!result.value) {
      attempts.push({ source: s.source, tier: s.tier, outcome: "not_found" });
      return;
    }
    attempts.push({ source: s.source, tier: s.tier, outcome: "found", score: result.value.score });
    found.push({ source: s.source, tier: s.tier, candidate: result.value.candidate, score: result.value.score });
  });

  if (found.length === 0) return { winner: null, attempts };

  const bestTier = Math.min(...found.map((f) => f.tier));
  const withinBestTier = found.filter((f) => f.tier === bestTier);
  withinBestTier.sort((a, b) => b.score - a.score);

  return { winner: withinBestTier[0], attempts };
}
