import { createClient } from "@/lib/supabase/server";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { RosterForm } from "./roster-form";
import { ConfirmButton } from "@/components/confirm-button";
import { removeRosterEntry } from "./actions";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Table, TableBody, TableRow, TableCell } from "@/components/organizer/ui/table";

export const dynamic = "force-dynamic";
type Roster = { id: string; organizer_id: string; entity_type: "person" | "ensemble"; entity_id: string };

export default async function AgencyPage() {
  const supabase = await createClient();
  const [organizers, { data: rosterData }, { data: persons }, { data: ensembles }] = await Promise.all([
    getEventOrganizerOptions(),
    supabase.from("organizer_agency_roster").select("id, organizer_id, entity_type, entity_id").returns<Roster[]>(),
    supabase.from("persons").select("id, full_name").order("full_name").limit(500),
    supabase.from("ensembles").select("id, name").order("name").limit(500),
  ]);
  const roster = rosterData ?? [];
  const entries = [...(persons ?? []).map((item) => ({ id: item.id as string, name: item.full_name as string, type: "person" as const })), ...(ensembles ?? []).map((item) => ({ id: item.id as string, name: item.name as string, type: "ensemble" as const }))];
  const nameById = new Map(entries.map((item) => [`${item.type}:${item.id}`, item.name]));
  const organizerById = new Map(organizers.map((item) => [item.id, item.name]));
  return (
    <div>
      <PageHeader
        eyebrow="Agentur"
        title="Agentur & Artist Roster"
        description="Verwalte Personen und Ensembles, die deine Agentur repräsentiert. Die Einträge bleiben zunächst rein redaktionell."
      />
      <PageBody className="mx-auto flex max-w-5xl flex-col gap-10">
        <RosterForm organizers={organizers} entries={entries} />
        <section className="flex flex-col gap-3">
          <h2 className="text-[13px] font-semibold uppercase tracking-wide text-[#726c78]">Mein Roster</h2>
          {roster.length === 0 ? (
            <Card>
              <CardContent className="pt-5 text-sm text-[#726c78]">Noch keine Künstler oder Ensembles hinzugefügt.</CardContent>
            </Card>
          ) : (
            <Table>
              <TableBody>
                {roster.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell className="font-medium">{nameById.get(`${item.entity_type}:${item.entity_id}`) ?? "Unbekanntes Profil"}</TableCell>
                    <TableCell>
                      <Badge>{item.entity_type === "person" ? "Person" : "Ensemble"}</Badge>
                    </TableCell>
                    <TableCell className="text-[#726c78]">{organizerById.get(item.organizer_id)}</TableCell>
                    <TableCell className="text-right">
                      <ConfirmButton
                        action={removeRosterEntry.bind(null, item.id)}
                        confirmMessage="Aus dem Roster entfernen?"
                        label="Entfernen"
                        pendingLabel="Entferne…"
                        className="text-sm font-medium text-[#a91551] hover:text-[#7a1929] disabled:opacity-50"
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </section>
      </PageBody>
    </div>
  );
}
