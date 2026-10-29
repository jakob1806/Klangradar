import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Button } from "@/components/organizer/ui/button";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Entwicklung der
// Follower der beanspruchten Profile (Person, Ensemble, Spielstätte). Nur
// Summen pro Tag, keine einzelnen Nutzer:innen. Die Verlaufsdaten entstehen
// per täglichem Schnappschuss ab dem 29.10.2026.

interface Audience {
  kind: "person" | "ensemble" | "venue";
  entity_id: string;
  name: string | null;
  followers: number;
  change_7d: number | null;
  change_30d: number | null;
  series: { day: string; n: number }[];
}

const KIND_LABEL: Record<Audience["kind"], string> = { person: "Person", ensemble: "Ensemble", venue: "Spielstätte" };

function Change({ value, label }: { value: number | null; label: string }) {
  if (value === null) return <span className="text-xs text-[#6B6B6B]">{label}: noch keine Daten</span>;
  const variant = value > 0 ? "success" : value < 0 ? "danger" : "default";
  return (
    <Badge variant={variant}>
      {value > 0 ? "+" : value < 0 ? "−" : "±"}
      {Math.abs(value).toLocaleString("de-DE")} {label}
    </Badge>
  );
}

function Sparkline({ series }: { series: Audience["series"] }) {
  if (series.length < 2) {
    return <p className="text-[13px] text-[#6B6B6B]">Der Verlauf erscheint, sobald ein paar Tage gesammelt sind.</p>;
  }
  const width = 320;
  const height = 64;
  const values = series.map((point) => point.n);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = Math.max(max - min, 1);
  const points = series
    .map((point, index) => `${((index / (series.length - 1)) * width).toFixed(1)},${(height - 4 - ((point.n - min) / span) * (height - 8)).toFixed(1)}`)
    .join(" ");
  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="h-16 w-full" role="img" aria-label={`Follower-Verlauf von ${values[0]} auf ${values[values.length - 1]}`}>
      <polyline points={points} fill="none" stroke="#2D2A6E" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

export default async function AudiencePage() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("organizer_audience");
  const rows = (data ?? []) as Audience[];
  const total = rows.reduce((sum, row) => sum + row.followers, 0);

  return (
    <div>
      <PageHeader
        eyebrow="Reichweite"
        title="Publikum"
        description="Wie viele Menschen euren Profilen in der App folgen und wie sich das entwickelt. Nur Summen – einzelne Personen sind nicht sichtbar."
      />
      <PageBody>
        {error ? (
          <p className="text-sm text-[#8a5a0c]">Die Publikumszahlen sind nach der nächsten Datenbank-Aktualisierung verfügbar.</p>
        ) : rows.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-start gap-3 pt-5 text-sm text-[#6B6B6B]">
              Follower gibt es für Personen, Ensembles und Spielstätten. Beansprucht ein Profil, um seine Entwicklung hier zu sehen.
              <Button asChild size="sm" variant="outline">
                <Link href="/veranstalter/claim">Profil beanspruchen</Link>
              </Button>
            </CardContent>
          </Card>
        ) : (
          <>
            <Card>
              <CardContent className="pt-5">
                <p className="text-sm text-[#6B6B6B]">Follower insgesamt</p>
                <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{total.toLocaleString("de-DE")}</p>
              </CardContent>
            </Card>
            <div className="mt-6 grid gap-3 lg:grid-cols-2">
              {rows.map((row) => (
                <Card key={`${row.kind}:${row.entity_id}`}>
                  <CardHeader className="flex-row items-start justify-between gap-3">
                    <div className="flex flex-col gap-1">
                      <CardTitle>{row.name ?? "Unbenannt"}</CardTitle>
                      <CardDescription>{KIND_LABEL[row.kind]}</CardDescription>
                    </div>
                    <p className="text-2xl font-semibold tabular-nums tracking-tight text-[#111111]">{row.followers.toLocaleString("de-DE")}</p>
                  </CardHeader>
                  <CardContent className="flex flex-col gap-3">
                    <Sparkline series={row.series} />
                    <div className="flex flex-wrap gap-2">
                      <Change value={row.change_7d} label="in 7 Tagen" />
                      <Change value={row.change_30d} label="in 30 Tagen" />
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </>
        )}
      </PageBody>
    </div>
  );
}
