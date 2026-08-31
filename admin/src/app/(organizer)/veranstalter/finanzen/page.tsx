import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Button } from "@/components/organizer/ui/button";
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
        <p className="text-sm text-[#726c78]">{label}</p>
        <p className="mt-1 text-3xl font-semibold tracking-tight text-[#15131a]">{value}</p>
        <p className="mt-2 text-xs leading-5 text-[#726c78]">{hint}</p>
      </CardContent>
    </Card>
  );
}

export default async function FinancesPage() {
  const supabase = await createClient();
  await getEventOrganizerOptions();
  const { data, error } = await supabase
    .from("event_promotions")
    .select("id, placement, status, payment_status, payment_amount_cents, payment_currency, requested_at, events(title, start_datetime)")
    .order("requested_at", { ascending: false })
    .returns<Promotion[]>();
  const promotions = data ?? [];
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
            {unknownHistoricalAmounts > 0 && (
              <p className="mt-4 text-xs leading-5 text-[#726c78]">
                Für {unknownHistoricalAmounts} frühere Zahlung{unknownHistoricalAmounts === 1 ? "" : "en"} wurde der Betrag noch nicht gespeichert. Neue Zahlungen werden automatisch vollständig erfasst.
              </p>
            )}

            <section className="mt-10 flex flex-col gap-3">
              <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Kampagnenkosten</h2>
              {promotions.length === 0 ? (
                <Card>
                  <CardContent className="pt-5 text-sm text-[#726c78]">Noch keine Promotionen gebucht.</CardContent>
                </Card>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Kampagne</TableHead>
                      <TableHead>Datum</TableHead>
                      <TableHead>Zahlung</TableHead>
                      <TableHead className="text-right">Betrag</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {promotions.map((promotion) => (
                      <TableRow key={promotion.id}>
                        <TableCell>
                          <p className="font-medium text-[#15131a]">{PLACEMENT_LABEL[promotion.placement] ?? promotion.placement}</p>
                          <p className="mt-0.5 text-xs text-[#726c78]">{promotion.events?.title ?? "Gelöschtes Event"}</p>
                        </TableCell>
                        <TableCell className="text-[#4a4550]">{promotion.events ? formatMunichDateTime(promotion.events.start_datetime) : "—"}</TableCell>
                        <TableCell className="text-[#4a4550]">{promotion.payment_status === "paid" ? "Bezahlt" : promotion.status === "payment_pending" ? "Ausstehend" : "Noch nicht fällig"}</TableCell>
                        <TableCell className="text-right font-medium tabular-nums text-[#15131a]">{formatAmount(promotion.payment_amount_cents, promotion.payment_currency)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </section>
          </>
        )}
      </PageBody>
    </div>
  );
}
