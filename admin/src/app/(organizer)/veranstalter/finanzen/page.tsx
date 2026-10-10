import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Button } from "@/components/organizer/ui/button";
import { BillingForm, type BillingProfile } from "./billing-form";
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/organizer/ui/table";

export const dynamic = "force-dynamic";

const PLACEMENT_LABEL: Record<string, string> = {
  standard: "Standard",
  featured: "Featured",
  local_spotlight: "Local Spotlight",
  homepage_feature: "Homepage Feature",
  push: "Push-Anfrage",
};

type Promotion = {
  id: string;
  placement: string;
  status: string;
  payment_status: string;
  payment_amount_cents: number | null;
  payment_currency: string | null;
  requested_at: string;
  events: { title: string; start_datetime: string } | null;
};

function formatAmount(cents: number | null, currency: string | null) {
  if (cents === null) return "—";
  return new Intl.NumberFormat("de-DE", {
    style: "currency",
    currency: (currency ?? "eur").toUpperCase(),
  }).format(cents / 100);
}

function SummaryCard({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <Card>
      <CardContent className="pt-5">
        <p className="text-sm text-[#6B6B6B]">{label}</p>
        <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{value}</p>
        <p className="mt-2 text-xs leading-5 text-[#6B6B6B]">{hint}</p>
      </CardContent>
    </Card>
  );
}

export default async function FinancesPage({ searchParams }: { searchParams: Promise<{ rechnung_fehler?: string }> }) {
  const { rechnung_fehler: invoiceError } = await searchParams;
  const supabase = await createClient();
  await getEventOrganizerOptions();
  const { data, error } = await supabase
    .from("event_promotions")
    .select("id, placement, status, payment_status, payment_amount_cents, payment_currency, requested_at, events(title, start_datetime)")
    .order("requested_at", { ascending: false })
    .returns<Promotion[]>();
  const promotions = data ?? [];
  const { data: billing } = await supabase.from("billing_profiles").select("name, street, zip, city, country, vat_id").maybeSingle<BillingProfile>();
  const { data: invoiceRows } = await supabase.from("promotion_invoices").select("promotion_id, invoice_number").returns<{ promotion_id: string; invoice_number: string }[]>();
  const invoiceNumbers = new Map((invoiceRows ?? []).map((row) => [row.promotion_id, row.invoice_number]));
  const paid = promotions.filter((promotion) => promotion.payment_status === "paid");
  const spendCents = paid.reduce((total, promotion) => total + (promotion.payment_amount_cents ?? 0), 0);
  const unknownHistoricalAmounts = paid.filter((promotion) => promotion.payment_amount_cents === null).length;
  const pending = promotions.filter((promotion) => promotion.status === "payment_pending").length;

  return (
    <div>
      <PageHeader
        eyebrow="Kosten"
        title="Finanzen"
        description="Deine über Klangradar gebuchten Promotionen und die dazugehörigen Stripe-Zahlungen."
        actions={
          <Button asChild>
            <Link href="/veranstalter/promote">Promotion buchen</Link>
          </Button>
        }
      />
      <PageBody>
        {error ? (
          <p className="text-sm text-[#8a5a0c]">Der Finanzbereich ist nach der nächsten Datenbank-Aktualisierung verfügbar.</p>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-3">
              <SummaryCard label="Bezahlte Ausgaben" value={formatAmount(spendCents, "EUR")} hint="Summe der gespeicherten Stripe-Zahlungen." />
              <SummaryCard label="Bezahlte Kampagnen" value={paid.length.toLocaleString("de-DE")} hint="Aktiv oder bereits abgeschlossen." />
              <SummaryCard label="Zahlung ausstehend" value={pending.toLocaleString("de-DE")} hint="Im Checkout noch nicht erfolgreich bezahlt." />
            </div>
            {invoiceError && (
              <p className="mt-4 rounded-xl bg-[#fdf1e3] px-4 py-3 text-sm text-[#8a5a0c]">{invoiceError}</p>
            )}
            {unknownHistoricalAmounts > 0 && (
              <p className="mt-4 text-xs leading-5 text-[#6B6B6B]">
                Für {unknownHistoricalAmounts} frühere Zahlung{unknownHistoricalAmounts === 1 ? "" : "en"} wurde der Betrag noch nicht gespeichert. Neue Zahlungen werden automatisch vollständig erfasst.
              </p>
            )}

            <section className="mt-10 flex flex-col gap-3">
              <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">Kampagnenkosten</h2>
              {promotions.length === 0 ? (
                <Card>
                  <CardContent className="pt-5 text-sm text-[#6B6B6B]">Noch keine Promotionen gebucht.</CardContent>
                </Card>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Kampagne</TableHead>
                      <TableHead>Datum</TableHead>
                      <TableHead>Zahlung</TableHead>
                      <TableHead className="text-right">Betrag</TableHead>
                      <TableHead className="text-right">Rechnung</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {promotions.map((promotion) => (
                      <TableRow key={promotion.id}>
                        <TableCell>
                          <p className="font-medium text-[#111111]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</p>
                          <p className="mt-0.5 text-xs text-[#6B6B6B]">{promotion.events?.title ?? "Gelöschtes Event"}</p>
                        </TableCell>
                        <TableCell className="text-[#4A4A4A]">{promotion.events ? formatMunichDateTime(promotion.events.start_datetime) : "—"}</TableCell>
                        <TableCell className="text-[#4A4A4A]">{promotion.payment_status === "paid" ? "Bezahlt" : promotion.status === "payment_pending" ? "Ausstehend" : "Noch nicht fällig"}</TableCell>
                        <TableCell className="text-right font-medium tabular-nums text-[#111111]">{formatAmount(promotion.payment_amount_cents, promotion.payment_currency)}</TableCell>
                        <TableCell className="text-right">
                          {promotion.payment_status === "paid" && promotion.payment_amount_cents !== null ? (
                            <a className="text-sm font-medium text-[#2D2A6E] underline" href={`/veranstalter/finanzen/rechnung/${promotion.id}`} target="_blank" rel="noreferrer">
                              {invoiceNumbers.get(promotion.id) ?? "Rechnung erstellen"} (PDF)
                            </a>
                          ) : (
                            <span className="text-xs text-[#6B6B6B]">—</span>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </section>

            <section className="mt-10 flex flex-col gap-3">
              <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">Rechnungsanschrift</h2>
              <Card>
                <CardContent className="pt-5">
                  <p className="mb-4 text-xs leading-5 text-[#6B6B6B]">Wird für Rechnungen bezahlter Promotionen benötigt und ist nur für dich und die Klangradar-Redaktion sichtbar. Bereits ausgestellte Rechnungen ändern sich nachträglich nicht.</p>
                  <BillingForm initial={billing ?? null} />
                </CardContent>
              </Card>
            </section>
          </>
        )}
      </PageBody>
    </div>
  );
}
