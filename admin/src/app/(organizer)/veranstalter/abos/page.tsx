import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { getEventOrganizerOptions } from "../event-organizer-context";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Input } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { SubmitButton } from "@/components/organizer/submit-button";
import { ActionForm } from "@/components/organizer/action-form";
import { addSubscriptionEvent, setSubscriptionEvent, updateOwnSubscription } from "./actions";

export const dynamic = "force-dynamic";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): eigene Abos und Zyklen
// pflegen — Name, Link und Termine — und sehen, wie viele Nutzer:innen in der
// App "Ich habe dieses Abo" gewählt haben (nur die Summe).

interface OwnSubscription {
  subscription_id: string;
  organizer_name: string;
  code: string;
  name: string;
  season: string;
  url: string | null;
  upcoming: number;
  total: number;
  members: number;
  next_start: string | null;
  edited_at: string | null;
}

interface LinkedEvent {
  subscription_id: string;
  event: { id: string; title: string; start_datetime: string; organizer_id: string | null } | null;
}

const selectClass =
  "h-9 w-full rounded-lg border border-[#DADADA] bg-white px-3 text-sm text-[#111111] transition hover:border-[#BDBDBD] focus-visible:border-[#111111] focus-visible:outline-none";

export default async function OrganizerSubscriptionsPage() {
  const supabase = await createClient();
  const organizers = await getEventOrganizerOptions();
  const organizerIds = organizers.map((organizer) => organizer.id);
  const { data, error } = await supabase.rpc("organizer_subscriptions");
  const subscriptions = (data ?? []) as OwnSubscription[];
  const ids = subscriptions.map((subscription) => subscription.subscription_id);
  const nowIso = new Date().toISOString();

  const [{ data: linkData }, { data: ownEventData }] = await Promise.all([
    ids.length
      ? supabase
          .from("event_concert_subscriptions")
          .select("subscription_id, event:events(id, title, start_datetime, organizer_id)")
          .in("subscription_id", ids)
      : Promise.resolve({ data: [] }),
    organizerIds.length
      ? supabase
          .from("events")
          .select("id, title, start_datetime")
          .in("organizer_id", organizerIds)
          .gte("start_datetime", nowIso)
          .in("status", ["scheduled", "sold_out"])
          .order("start_datetime")
          .limit(300)
      : Promise.resolve({ data: [] }),
  ]);
  const links = ((linkData ?? []) as unknown as LinkedEvent[]).filter((link) => link.event && link.event.start_datetime >= nowIso);
  const ownEvents = (ownEventData ?? []) as { id: string; title: string; start_datetime: string }[];
  const members = subscriptions.reduce((sum, subscription) => sum + subscription.members, 0);

  return (
    <div>
      <PageHeader
        eyebrow="Programm"
        title="Abos"
        description="Eure Abos und Zyklen, wie sie in der App erscheinen. Name, Link und Termine könnt ihr hier korrigieren – der automatische Import überschreibt bearbeitete Abos nicht mehr."
      />
      <PageBody>
        {error ? (
          <p className="text-sm text-[#8a5a0c]">Die Abos sind nach der nächsten Datenbank-Aktualisierung verfügbar.</p>
        ) : subscriptions.length === 0 ? (
          <Card>
            <CardContent className="pt-5 text-sm text-[#6B6B6B]">
              Zu euren Terminen sind noch keine Abos bekannt. Sobald der Import Abos erkennt, erscheinen sie hier.
            </CardContent>
          </Card>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-3">
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#6B6B6B]">Abos</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{subscriptions.length}</p>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#6B6B6B]">Kommende Abo-Termine</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">
                    {subscriptions.reduce((sum, subscription) => sum + subscription.upcoming, 0).toLocaleString("de-DE")}
                  </p>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="pt-5">
                  <p className="text-sm text-[#6B6B6B]">„Ich habe dieses Abo“</p>
                  <p className="mt-1 text-3xl font-semibold tracking-tight text-[#111111]">{members.toLocaleString("de-DE")}</p>
                  <p className="mt-1 text-xs text-[#6B6B6B]">Summe, ohne persönliche Daten</p>
                </CardContent>
              </Card>
            </div>

            <div className="mt-8 flex flex-col gap-4">
              {subscriptions.map((subscription) => {
                const events = links
                  .filter((link) => link.subscription_id === subscription.subscription_id)
                  .map((link) => link.event!)
                  .sort((a, b) => a.start_datetime.localeCompare(b.start_datetime));
                const linkedIds = new Set(events.map((event) => event.id));
                const addable = ownEvents.filter((event) => !linkedIds.has(event.id));
                return (
                  <Card key={subscription.subscription_id}>
                    <CardHeader className="flex-row flex-wrap items-start justify-between gap-3">
                      <div className="flex flex-col gap-1">
                        <CardTitle>{subscription.name}</CardTitle>
                        <CardDescription>
                          {subscription.organizer_name} · Saison {subscription.season} · {subscription.code}
                        </CardDescription>
                      </div>
                      <div className="flex flex-wrap gap-1.5">
                        <Badge>{subscription.upcoming} kommende Termine</Badge>
                        <Badge variant="accent">{subscription.members} mit Abo</Badge>
                        {subscription.edited_at && <Badge variant="success">bearbeitet</Badge>}
                      </div>
                    </CardHeader>
                    <CardContent className="grid gap-6 lg:grid-cols-2">
                      <ActionForm action={updateOwnSubscription.bind(null, subscription.subscription_id)} className="flex flex-col gap-3">
                        <div className="flex flex-col gap-1.5">
                          <Label htmlFor={`name-${subscription.subscription_id}`}>Name</Label>
                          <Input id={`name-${subscription.subscription_id}`} name="name" required defaultValue={subscription.name} />
                        </div>
                        <div className="flex flex-col gap-1.5">
                          <Label htmlFor={`url-${subscription.subscription_id}`}>Link zur Abo-Seite</Label>
                          <Input id={`url-${subscription.subscription_id}`} name="url" type="url" placeholder="https://" defaultValue={subscription.url ?? ""} />
                        </div>
                        <div>
                          <SubmitButton size="sm">Speichern</SubmitButton>
                        </div>
                      </ActionForm>

                      <div className="flex flex-col gap-3">
                        <p className="text-[13px] font-medium text-[#111111]">Kommende Termine</p>
                        {events.length === 0 ? (
                          <p className="text-[13px] text-[#6B6B6B]">Keine kommenden Termine zugeordnet.</p>
                        ) : (
                          <ul className="flex flex-col divide-y divide-[#F0F0F0] rounded-lg border border-[#EAEAEA]">
                            {events.map((event) => (
                              <li key={event.id} className="flex items-center justify-between gap-3 px-3 py-2">
                                <span className="min-w-0">
                                  <Link href={`/veranstalter/events/${event.id}`} className="block truncate text-[13.5px] font-medium text-[#111111] hover:text-[#2D2A6E]">
                                    {event.title}
                                  </Link>
                                  <span className="text-xs text-[#6B6B6B]">{formatMunichDateTime(event.start_datetime)}</span>
                                </span>
                                {event.organizer_id && organizerIds.includes(event.organizer_id) && (
                                  <form action={setSubscriptionEvent.bind(null, subscription.subscription_id, event.id, false)}>
                                    <SubmitButton size="sm" variant="ghost" pendingLabel="…">
                                      Entfernen
                                    </SubmitButton>
                                  </form>
                                )}
                              </li>
                            ))}
                          </ul>
                        )}
                        {addable.length > 0 && (
                          <ActionForm action={addSubscriptionEvent.bind(null, subscription.subscription_id)} className="flex flex-wrap items-center gap-2">
                            <select name="event_id" defaultValue="" aria-label="Termin hinzufügen" className={`${selectClass} min-w-0 flex-1`}>
                              <option value="" disabled>
                                Eigenen Termin hinzufügen …
                              </option>
                              {addable.map((event) => (
                                <option key={event.id} value={event.id}>
                                  {formatMunichDateTime(event.start_datetime)} · {event.title}
                                </option>
                              ))}
                            </select>
                            <SubmitButton size="sm" variant="outline" pendingLabel="Füge hinzu …">
                              Hinzufügen
                            </SubmitButton>
                          </ActionForm>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          </>
        )}
      </PageBody>
    </div>
  );
}
