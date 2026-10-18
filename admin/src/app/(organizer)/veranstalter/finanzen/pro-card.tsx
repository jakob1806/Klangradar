import { formatMunichDateTime } from "@/lib/munich-time";
import { PRO_BENEFITS, PRO_MONTHLY_CENTS, type ProStatus } from "@/lib/portal-pro";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Button } from "@/components/organizer/ui/button";
import { openPortalPro } from "./pro-actions";

const PRICE = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(PRO_MONTHLY_CENTS / 100);

export function ProCard({ organizers, statuses, notice }: { organizers: { id: string; name: string }[]; statuses: Map<string, ProStatus>; notice?: string }) {
  if (!organizers.length) return null;
  return (
    <section className="mt-10 flex flex-col gap-3">
      <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#6B6B6B]">Portal Pro</h2>
      {notice === "success" && <p className="rounded-xl bg-[#EEF6F1] px-4 py-3 text-sm text-[#1F7A4D]">Danke! Portal Pro ist aktiv, sobald Stripe die Zahlung bestätigt hat (meist sofort).</p>}
      {notice === "error" && <p className="rounded-xl bg-[#FDECEA] px-4 py-3 text-sm text-[#B42318]">Der Abo-Abschluss konnte nicht geöffnet werden. Bitte versuche es später erneut.</p>}
      <Card>
        <CardContent className="grid gap-6 pt-5 md:grid-cols-[1fr_1.2fr]">
          <div>
            <p className="text-2xl font-semibold tracking-tight text-[#111111]">
              {PRICE}
              <span className="text-sm font-normal text-[#6B6B6B]"> / Monat, monatlich kündbar</span>
            </p>
            <ul className="mt-3 space-y-1.5 text-sm text-[#4A4A4A]">
              {PRO_BENEFITS.map((benefit) => (
                <li key={benefit} className="flex gap-2">
                  <span className="text-[#2D2A6E]">✓</span>
                  {benefit}
                </li>
              ))}
            </ul>
          </div>
          <div className="divide-y divide-[#111111]/[0.06] rounded-lg border border-[#111111]/[0.08]">
            {organizers.map((organizer) => {
              const status = statuses.get(organizer.id);
              return (
                <div key={organizer.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-[#111111]">{organizer.name}</p>
                    {status?.active ? (
                      <p className="text-xs text-[#6B6B6B]">
                        {status.used} von {status.limit} Platzierungen genutzt
                        {status.periodEnd ? ` · ${status.cancelAtPeriodEnd ? "endet" : "verlängert sich"} am ${formatMunichDateTime(status.periodEnd).split(",")[0]}` : ""}
                      </p>
                    ) : (
                      <p className="text-xs text-[#6B6B6B]">{status?.status === "past_due" ? "Zahlung offen" : "Kein Abo"}</p>
                    )}
                  </div>
                  {status?.active ? <Badge variant="success">Pro</Badge> : null}
                  <form action={openPortalPro}>
                    <input type="hidden" name="organizer_id" value={organizer.id} />
                    <Button type="submit" size="sm" variant={status?.active ? "outline" : "default"}>
                      {status?.active ? "Abo verwalten" : "Pro abschließen"}
                    </Button>
                  </form>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>
    </section>
  );
}
