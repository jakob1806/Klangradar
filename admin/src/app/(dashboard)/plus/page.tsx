import { createClient } from "@/lib/supabase/server";
import { SubmitButton } from "@/components/submit-button";
import { AdminPageHeader, EmptyRow, StatTile, TableFrame, Th, dayMonthYear, inputClass, tbodyClass, theadClass } from "@/components/admin-kit";
import { createPlusCode } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Klangradar Plus auf
// einen Blick — aktive Freischaltungen nach Quelle, Abläufe, Code-Einlösungen
// und Verwaltung der Freischalt-Codes. Nur Summen, keine einzelnen Konten.
// Käufe im App Store erscheinen erst vollständig, wenn die App Store Server
// Notifications angebunden sind; bis dahin meldet nur die App selbst.

interface Overview {
  active: number;
  active_app_store: number;
  active_code: number;
  unlimited: number;
  expiring_14d: number;
  expired_30d: number;
  new_30d: number;
  redemptions_30d: number;
}

interface PlusCode {
  code: string;
  allowed_email: string | null;
  duration_days: number | null;
  max_uses: number;
  uses: number;
  valid_until: string | null;
  note: string | null;
  created_at: string;
}

export default async function PlusPage() {
  const supabase = await createClient();
  const [{ data: overviewData, error: overviewError }, { data: codeData, error: codeError }] = await Promise.all([
    supabase.rpc("admin_plus_overview"),
    supabase.rpc("admin_plus_codes"),
  ]);
  const overview = overviewData as Overview | null;
  const codes = (codeData ?? []) as PlusCode[];
  const error = overviewError ?? codeError;

  if (!error && !overview) {
    return (
      <div className="p-8">
        <AdminPageHeader title="Klangradar Plus" />
        <p className="mt-4 text-sm text-neutral-600">Diese Übersicht ist nur für Admins sichtbar.</p>
      </div>
    );
  }

  return (
    <div className="p-8">
      <AdminPageHeader
        title="Klangradar Plus"
        description="Aktive Freischaltungen, Abläufe und Freischalt-Codes. Nur Summen, keine einzelnen Konten."
      />

      <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
        App-Store-Käufe, Verlängerungen und Kündigungen kommen erst vollständig an, wenn die App Store Server Notifications eingerichtet sind. Bis dahin
        meldet nur die App selbst einen Kauf, Kündigungen fehlen.
      </div>

      {error && <p className="mt-4 text-sm text-amber-700">Konnte Daten nicht laden: {error.message}</p>}

      {overview && (
        <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <StatTile label="Aktiv" value={overview.active} hint={`${overview.active_app_store} App Store · ${overview.active_code} per Code`} />
          <StatTile label="Neu (30 Tage)" value={overview.new_30d} hint={`${overview.redemptions_30d} Code-Einlösungen`} />
          <StatTile label="Läuft bald ab" value={overview.expiring_14d} hint="in den nächsten 14 Tagen" />
          <StatTile label="Abgelaufen (30 Tage)" value={overview.expired_30d} hint={`${overview.unlimited} unbefristet aktiv`} />
        </div>
      )}

      <div className="mt-10 grid gap-6 lg:grid-cols-[1fr_320px]">
        <div>
          <h2 className="text-base font-semibold text-neutral-900">Freischalt-Codes</h2>
          <TableFrame>
            <table className="w-full text-sm">
              <thead className={theadClass}>
                <tr>
                  <Th>Code</Th>
                  <Th>Dauer</Th>
                  <Th>Eingelöst</Th>
                  <Th>Gültig bis</Th>
                  <Th>Notiz</Th>
                </tr>
              </thead>
              <tbody className={tbodyClass}>
                {codes.map((code) => (
                  <tr key={code.code} className="align-top">
                    <td className="px-4 py-3">
                      <p className="font-mono text-[13px] font-medium text-neutral-900">{code.code}</p>
                      {code.allowed_email && <p className="text-xs text-neutral-500">nur für {code.allowed_email}</p>}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">{code.duration_days ? `${code.duration_days} Tage` : "unbefristet"}</td>
                    <td className="whitespace-nowrap px-4 py-3 tabular-nums">
                      {code.uses} / {code.max_uses}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">{code.valid_until ? dayMonthYear.format(new Date(code.valid_until)) : "–"}</td>
                    <td className="px-4 py-3 text-neutral-600">{code.note ?? ""}</td>
                  </tr>
                ))}
                {!codeError && codes.length === 0 && <EmptyRow colSpan={5}>Noch keine Codes.</EmptyRow>}
              </tbody>
            </table>
          </TableFrame>
        </div>

        <form action={createPlusCode} className="flex h-fit flex-col gap-3 rounded-xl border border-black/[0.06] bg-white p-4 shadow-sm">
          <h2 className="text-base font-semibold text-neutral-900">Neuer Code</h2>
          <label className="text-xs font-medium text-neutral-600">
            Code
            <input name="code" required pattern="[A-Za-z0-9-]{4,40}" placeholder="z. B. PRESSE-2026" className={`${inputClass} mt-1 w-full font-mono uppercase`} />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="text-xs font-medium text-neutral-600">
              Dauer in Tagen
              <input name="duration_days" type="number" min={0} placeholder="leer = unbefristet" className={`${inputClass} mt-1 w-full`} />
            </label>
            <label className="text-xs font-medium text-neutral-600">
              Einlösungen
              <input name="max_uses" type="number" min={1} defaultValue={1} className={`${inputClass} mt-1 w-full`} />
            </label>
          </div>
          <label className="text-xs font-medium text-neutral-600">
            Einlösbar bis (optional)
            <input name="valid_until" type="date" className={`${inputClass} mt-1 w-full`} />
          </label>
          <label className="text-xs font-medium text-neutral-600">
            Nur für E-Mail (optional)
            <input name="allowed_email" type="email" className={`${inputClass} mt-1 w-full`} />
          </label>
          <label className="text-xs font-medium text-neutral-600">
            Notiz
            <input name="note" placeholder="Wofür ist der Code?" className={`${inputClass} mt-1 w-full`} />
          </label>
          <div>
            <SubmitButton pendingLabel="Lege an …">Code anlegen</SubmitButton>
          </div>
        </form>
      </div>
    </div>
  );
}
