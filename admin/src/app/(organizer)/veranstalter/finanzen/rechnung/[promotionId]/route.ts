import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { renderInvoicePdf, type InvoiceData } from "@/lib/invoice-pdf";

export const dynamic = "force-dynamic";

export async function GET(request: Request, { params }: { params: Promise<{ promotionId: string }> }) {
  const { promotionId } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const base = new URL(request.url);
  const back = (message: string) =>
    NextResponse.redirect(new URL(`/veranstalter/finanzen?rechnung_fehler=${encodeURIComponent(message)}`, base));
  if (!user) return NextResponse.redirect(new URL("/login?next=/veranstalter/finanzen", base));

  const { data: number, error } = await supabase.rpc("issue_promotion_invoice", { p_promotion_id: promotionId });
  if (error || !number) return back(error?.message ?? "Die Rechnung konnte nicht erstellt werden.");

  const { data: invoice } = await supabase
    .from("promotion_invoices")
    .select("invoice_number, issued_on, service_from, service_to, description, net_cents, vat_cents, gross_cents, vat_rate, small_business, issuer, recipient")
    .eq("promotion_id", promotionId)
    .maybeSingle<InvoiceData>();
  if (!invoice) return back("Die Rechnung wurde nicht gefunden.");

  const pdf = await renderInvoicePdf(invoice);
  return new NextResponse(Buffer.from(pdf), {
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `inline; filename="Rechnung-${invoice.invoice_number}.pdf"`,
      "Cache-Control": "private, no-store",
    },
  });
}
