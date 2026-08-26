"use client";

// Nutzeranfrage: "in allen Tabs, in denen eine Liste an verschiedenen
// Dingen wie Venues, Ensembles, Künstler, Veranstaltungen usw. fehlt eine
// Suchfunktion". Für die nicht paginierten Listen (Personen/Ensembles/
// Venues sind komplett auf einer Seite geladen) reicht ein reiner Client-
// Filter — kein Server-Roundtrip nötig. Bewusst als direkte DOM-Filterung
// statt React-State-getriebenem Re-Render der Zeilen: die Tabellen bleiben
// normale Server-gerenderte JSX (inkl. bereits vorhandener Mehrfachauswahl-
// Checkboxen aus bio-select.tsx), dieser Filter schaltet nur die
// Sichtbarkeit der Zeilen um, statt die Zeilen-Rendering-Logik in eine
// eigene Client-Komponente ziehen zu müssen.
export function TableSearchFilter({
  containerId,
  placeholder = "Suchen…",
}: {
  containerId: string;
  placeholder?: string;
}) {
  function handleChange(value: string) {
    const container = document.getElementById(containerId);
    if (!container) return;
    const query = value.trim().toLowerCase();
    const rows = container.querySelectorAll<HTMLElement>("tr[data-search]");
    rows.forEach((row) => {
      const match = !query || (row.dataset.search ?? "").includes(query);
      row.dataset.hiddenBySearch = match ? "" : "1";
      row.style.display = row.dataset.hiddenBySearch === "1" || row.dataset.hiddenByCity === "1" ? "none" : "";
    });
  }

  return (
    <input
      type="search"
      placeholder={placeholder}
      onChange={(e) => handleChange(e.target.value)}
      className="mb-4 w-full max-w-xs rounded-lg border border-black/10 px-3 py-2 text-sm outline-none focus:border-[#0071e3]"
    />
  );
}
