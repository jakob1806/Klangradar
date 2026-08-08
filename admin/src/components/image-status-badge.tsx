/** Sichtbarer Hinweis, ob bereits ein Bild vorliegt — Analogon zu
 * BioStatusBadge (bio-select.tsx). Nutzerwunsch: "auch soll, wie mit bio
 * vorhanden sichtbar ist, ob ein bild vorhanden ist. sowohl bei
 * veranstaltungen als auch bei allen anderen wie personen" — bisher stand
 * dieser Hinweis nur INNERHALB der Bilder-Recherche-Auswahl
 * (image-research/page.tsx), nicht auf den eigentlichen Verwaltungslisten
 * (Personen/Venues/Ensembles/Veranstaltungen), wo die analoge Bio-Anzeige
 * schon länger existiert. */
export function ImageStatusBadge({ hasImage }: { hasImage: boolean }) {
  return (
    <span
      className={`rounded-full px-2.5 py-1 text-xs font-medium ${
        hasImage ? "bg-blue-50 text-blue-700" : "bg-neutral-100 text-neutral-400"
      }`}
    >
      {hasImage ? "Bild vorhanden" : "Kein Bild"}
    </span>
  );
}
