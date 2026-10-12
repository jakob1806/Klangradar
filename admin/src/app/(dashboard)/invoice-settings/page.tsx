import { createClient } from "@/lib/supabase/server";
import { InvoiceSettingsForm, type InvoiceSettings } from "./settings-form";

export const dynamic = "force-dynamic";

export default async function InvoiceSettingsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.from("invoice_settings").select("*").eq("id", 1).maybeSingle<InvoiceSettings>();
  const ready = Boolean(data && (data.tax_number || data.vat_id) && data.iban);
  return (
    <div className="p-8">
      <h1 className="text-xl font-semibold tracking-tight">Rechnungsstammdaten</h1>
      <p className="mt-1 max-w-2xl text-sm text-neutral-500">Absenderangaben für die Rechnungen bezahlter Promotionen. Bereits ausgestellte Rechnungen bleiben unverändert (Snapshot).</p>
      <p className={`mt-3 inline-block rounded-full px-3 py-1 text-xs font-semibold ${ready ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-800"}`}>
        {ready ? "Rechnungsstellung aktiv" : "Rechnungsstellung noch gesperrt: Steuernummer/USt-IdNr. und IBAN fehlen"}
      </p>
      <div className="mt-8">
        {error || !data ? <p className="text-sm text-amber-700">Die Stammdaten konnten nicht geladen werden{error ? `: ${error.message}` : ""}.</p> : <InvoiceSettingsForm settings={data} />}
      </div>
    </div>
  );
}
