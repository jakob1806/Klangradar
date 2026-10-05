import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";

export type InvoiceData = {
  invoice_number: string;
  issued_on: string;
  service_from: string | null;
  service_to: string | null;
  description: string;
  net_cents: number;
  vat_cents: number;
  gross_cents: number;
  vat_rate: number;
  small_business: boolean;
  issuer: Record<string, string | null>;
  recipient: Record<string, string | null>;
};

const eur = (cents: number) =>
  new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(cents / 100).replace(/ /g, " ");

const date = (value: string | null) =>
  value ? new Intl.DateTimeFormat("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium" }).format(new Date(value)) : null;

export async function renderInvoicePdf(inv: InvoiceData): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  pdf.setTitle(`Rechnung ${inv.invoice_number}`);
  pdf.setCreator("Klangradar");
  const page = pdf.addPage([595.28, 841.89]); // A4
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const ink = rgb(0.08, 0.07, 0.1);
  const muted = rgb(0.45, 0.42, 0.47);
  const left = 56;
  const right = 595.28 - 56;

  const text = (p: PDFPage, s: string, x: number, y: number, size = 10, f: PDFFont = font, color = ink) =>
    p.drawText(s, { x, y, size, font: f, color });
  const textRight = (s: string, y: number, size = 10, f: PDFFont = font, edge = right) =>
    text(page, s, edge - f.widthOfTextAtSize(s, size), y, size, f);

  const i = inv.issuer;
  const issuerLines = [i.issuer_name, i.issuer_street, `${i.issuer_zip} ${i.issuer_city}`, i.issuer_country].filter(Boolean) as string[];

  // Kopf
  text(page, "Rechnung", left, 780, 24, bold, rgb(0.176, 0.165, 0.431));
  text(page, "Klangradar", right - bold.widthOfTextAtSize("Klangradar", 14), 784, 14, bold, rgb(0.176, 0.165, 0.431));

  // Absenderzeile (Fensterumschlag) und Empfänger
  text(page, `${i.issuer_name} · ${i.issuer_street} · ${i.issuer_zip} ${i.issuer_city}`, left, 735, 7, font, muted);
  const r = inv.recipient;
  const recipientLines = [r.name, r.street, `${r.zip} ${r.city}`, r.country !== "Deutschland" ? r.country : null, r.vat_id ? `USt-IdNr.: ${r.vat_id}` : null].filter(Boolean) as string[];
  recipientLines.forEach((line, n) => text(page, line!, left, 715 - n * 14, 10.5));

  // Metadaten rechts
  const meta: [string, string][] = [
    ["Rechnungsnummer", inv.invoice_number],
    ["Rechnungsdatum", date(inv.issued_on)!],
  ];
  const period = inv.service_from && inv.service_to ? `${date(inv.service_from)} – ${date(inv.service_to)}` : date(inv.service_from) ?? date(inv.issued_on)!;
  meta.push(["Leistungszeitraum", period]);
  if (i.tax_number) meta.push(["Steuernummer", i.tax_number]);
  if (i.vat_id) meta.push(["USt-IdNr.", i.vat_id]);
  meta.forEach(([k, v], n) => {
    const y = 715 - n * 14;
    text(page, k, 340, y, 9, font, muted);
    textRight(v, y, 9.5, bold);
  });

  // Positionstabelle
  let y = 590;
  text(page, "Beschreibung", left, y, 9, bold, muted);
  textRight("Betrag (netto)", y, 9, bold);
  page.drawLine({ start: { x: left, y: y - 6 }, end: { x: right, y: y - 6 }, thickness: 0.6, color: muted });
  y -= 24;

  const words = inv.description.split(" ");
  const lines: string[] = [];
  let cur = "";
  for (const w of words) {
    const next = cur ? `${cur} ${w}` : w;
    if (font.widthOfTextAtSize(next, 10.5) > 330) { lines.push(cur); cur = w; } else cur = next;
  }
  if (cur) lines.push(cur);
  lines.forEach((l, n) => text(page, l, left, y - n * 14, 10.5));
  textRight(eur(inv.net_cents), y, 10.5);
  y -= lines.length * 14 + 14;

  page.drawLine({ start: { x: 330, y }, end: { x: right, y }, thickness: 0.4, color: muted });
  y -= 18;
  text(page, "Zwischensumme (netto)", 330, y, 10);
  textRight(eur(inv.net_cents), y);
  y -= 16;
  if (!inv.small_business) {
    text(page, `Umsatzsteuer ${inv.vat_rate.toLocaleString("de-DE")} %`, 330, y, 10);
    textRight(eur(inv.vat_cents), y);
    y -= 16;
  }
  page.drawLine({ start: { x: 330, y: y + 10 }, end: { x: right, y: y + 10 }, thickness: 0.4, color: muted });
  text(page, "Rechnungsbetrag", 330, y - 4, 11, bold);
  textRight(eur(inv.gross_cents), y - 4, 11, bold);
  y -= 40;

  if (inv.small_business) {
    text(page, "Gemäß § 19 UStG wird keine Umsatzsteuer berechnet.", left, y, 9.5);
    y -= 16;
  }
  text(page, "Der Betrag wurde bereits per Kartenzahlung/Online-Zahlung über Stripe beglichen. Es ist keine weitere Zahlung erforderlich.", left, y, 9.5);

  // Fußzeile
  const footer = [
    issuerLines.join(" · "),
    [i.email, i.phone].filter(Boolean).join(" · "),
    [i.iban ? `IBAN ${i.iban}` : null, i.bic ? `BIC ${i.bic}` : null].filter(Boolean).join(" · "),
  ].filter(Boolean);
  footer.forEach((l, n) => text(page, l, left, 60 - n * 11, 8, font, muted));

  return pdf.save();
}
