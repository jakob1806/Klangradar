"use client";

// Nutzerfeedback: "die generelle differenzierung zwischen städten oder
// alle städte anzeigen im admindashboard" fehlte komplett auf den
// Listenseiten. Gleiches Client-Filter-Muster wie table-search-filter.tsx
// (Zeilen per data-Attribut ein-/ausblenden, kein Server-Roundtrip), aber
// unabhängig kombinierbar mit dem Suchfeld: beide Filter setzen ihr
// eigenes data-hidden-by-*-Flag auf der Zeile statt sich gegenseitig über
// style.display zu überschreiben, die Zeile wird nur sichtbar, wenn kein
// Flag gesetzt ist.
export function CityFilter({
  containerId,
  regions,
}: {
  containerId: string;
  regions: { id: string; name: string }[];
}) {
  function handleChange(regionId: string) {
    const container = document.getElementById(containerId);
    if (!container) return;
    const rows = container.querySelectorAll<HTMLElement>("tr[data-region]");
    rows.forEach((row) => {
      const match = !regionId || row.dataset.region === regionId;
      row.dataset.hiddenByCity = match ? "" : "1";
      row.style.display = row.dataset.hiddenBySearch === "1" || row.dataset.hiddenByCity === "1" ? "none" : "";
    });
  }

  return (
    <select
      onChange={(e) => handleChange(e.target.value)}
      defaultValue=""
      className="mb-4 rounded-lg border border-black/10 px-3 py-2 text-sm outline-none focus:border-[#0071e3]"
    >
      <option value="">Alle Städte</option>
      {regions.map((r) => (
        <option key={r.id} value={r.id}>
          {r.name}
        </option>
      ))}
    </select>
  );
}
