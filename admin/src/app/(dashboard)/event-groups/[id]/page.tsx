import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { DeleteButton } from "@/components/delete-button";
import { removeEventFromGroup } from "../actions";
import { EventChecklist } from "./event-checklist";
import { GroupImageUploader } from "./group-image-uploader";
import { GroupParticipantImporter } from "./group-participant-importer";
import { MembershipEditor } from "./membership-editor";
import { MoveButtons } from "../../events/[id]/program/move-buttons";
import { EntitySearch } from "../../events/[id]/program/entity-search";
import { EventFinder } from "./event-finder";
import { ParticipantBulkAdder } from "./participant-bulk-adder";
import { formatMunichDateTime } from "@/lib/munich-time";
import {
  addExistingWorkToGroup,

  alignGroupLineup,
  copyLineupFromEvent,
  setParticipantRoleInGroup,
  createEnsembleAndAddToGroup,
  createPersonAndAddToGroup,
  createWorkAndAddToGroup,
  moveWorkInGroup,
  removeParticipantFromGroup,
  removeWorkFromGroup,
  setParticipantEventMembership,
  setWorkEventMembership,
} from "./actions";

const ROLE_LABEL: Record<string, string> = {
  komponist: "Komponist:in",
  dirigent: "Dirigent:in",
  solist: "Solist:in",
  chorleiter: "Chorleiter:in",
  moderator: "Moderator:in",
};

function formatDate(iso: string) {
  return formatMunichDateTime(iso);
}

interface MemberEvent {
  id: string;
  title: string;
  start_datetime: string;
  venues: { name: string } | null;
}

interface ProgramWorkRow {
  event_id: string;
  work_id: string;
  position: number;
  after_intermission: boolean;
  works: { title: string; catalog_number: string | null; composer: { full_name: string } | null } | null;
}

interface ParticipantRow {
  event_id: string;
  person_id: string | null;
  ensemble_id: string | null;
  role: string | null;
  role_label: string | null;
  persons: { full_name: string } | null;
  ensembles: { name: string } | null;
}

export default async function EventGroupDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: group } = await supabase.from("programs").select("id, title").eq("id", id).maybeSingle();
  if (!group) notFound();

  const { data: members } = await supabase
    .from("events")
    .select("id, title, start_datetime, venues(name)")
    .eq("program_id", id)
    .order("start_datetime", { ascending: true })
    .returns<MemberEvent[]>();

  const memberIds = (members ?? []).map((e) => e.id);
  const checklistEvents = (members ?? []).map((e) => ({
    id: e.id,
    label: `${formatDate(e.start_datetime)}${e.venues?.name ? ` · ${e.venues.name}` : ""}`,
  }));
  const allMemberIdsSet = new Set(memberIds);

  // Nutzeranfrage: "in der Bearbeitungsansicht soll angezeigt werden, wenn
  // schon ein Bild für die Gruppe vorhanden ist, und auch welches" —
  // addGroupImage trägt dasselbe Bild bei JEDEM Mitgliedsevent an Position 0
  // ein (siehe actions.ts), es gibt keine eigene Gruppen-Bild-Spalte. Das
  // "aktuelle" Gruppenbild wird deshalb als die unter den Terminen häufigste
  // sourceUrl an Position 0 ermittelt — im Normalfall identisch bei allen,
  // die Abdeckungszahl macht aber sichtbar, falls z.B. ein neu hinzugefügter
  // Termin das Bild noch nicht hat.
  let groupImageUrl: string | null = null;
  let groupImageCoverage = 0;
  if (memberIds.length > 0) {
    const { data: topImages } = await supabase
      .from("images")
      .select("origin_id, source_url")
      .eq("origin_type", "event")
      .in("origin_id", memberIds)
      .eq("sort_order", 0)
      .in("license_status", ["confirmed_free", "confirmed_licensed"]);
    const counts = new Map<string, number>();
    for (const row of topImages ?? []) {
      if (!row.source_url) continue;
      counts.set(row.source_url, (counts.get(row.source_url) ?? 0) + 1);
    }
    const dominant = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
    if (dominant) {
      groupImageUrl = dominant[0];
      groupImageCoverage = dominant[1];
    }
  }

  // Keine Komplettlisten von Werken/Personen/Ensembles/Events mehr laden
  // (PostgREST kappt bei 1000 Zeilen) – Auswahl läuft über Serversuche.
  const [{ data: workRows }, { data: participantRows }] =
    memberIds.length > 0
      ? await Promise.all([
          supabase
            .from("event_works")
            .select("event_id, work_id, position, after_intermission, works(title, catalog_number, composer:persons(full_name))")
            .in("event_id", memberIds)
            .order("position", { ascending: true })
            .returns<ProgramWorkRow[]>(),
          supabase
            .from("event_participants")
            .select("event_id, person_id, ensemble_id, role, role_label, persons(full_name), ensembles(name)")
            .in("event_id", memberIds)
            .returns<ParticipantRow[]>(),
        ])
      : [{ data: [] }, { data: [] }];

  // Werke/Mitwirkende sind über die Broadcast-Actions eigentlich auf allen
  // Mitgliedsevents identisch — dedupliziert dargestellt, mit Hinweis und
  // Bearbeiten-Möglichkeit, falls ein Event (noch) abweicht.
  const workMap = new Map<
    string,
    { work: ProgramWorkRow["works"]; afterIntermission: boolean; eventIds: Set<string> }
  >();
  for (const row of workRows ?? []) {
    const existing = workMap.get(row.work_id);
    if (existing) existing.eventIds.add(row.event_id);
    else
      workMap.set(row.work_id, {
        work: row.works,
        afterIntermission: row.after_intermission,
        eventIds: new Set([row.event_id]),
      });
  }

  const participantMap = new Map<
    string,
    {
      label: string;
      role: string | null;
      roleLabel: string | null;
      personId: string | null;
      ensembleId: string | null;
      eventIds: Set<string>;
    }
  >();
  for (const row of participantRows ?? []) {
    const key = row.person_id ?? `ensemble:${row.ensemble_id}`;
    const existing = participantMap.get(key);
    if (existing) existing.eventIds.add(row.event_id);
    else
      participantMap.set(key, {
        label: row.persons?.full_name ?? row.ensembles?.name ?? "?",
        role: row.role,
        roleLabel: row.role_label,
        personId: row.person_id,
        ensembleId: row.ensemble_id,
        eventIds: new Set([row.event_id]),
      });
  }

  const memberCount = memberIds.length;
  const boundAddExistingWork = addExistingWorkToGroup.bind(null, id);
  const boundCreateWorkAndAdd = createWorkAndAddToGroup.bind(null, id);
  const boundCreatePerson = createPersonAndAddToGroup.bind(null, id);
  const boundCreateEnsemble = createEnsembleAndAddToGroup.bind(null, id);


  const participantCountByEvent = new Map<string, number>();
  for (const row of participantRows ?? []) {
    participantCountByEvent.set(row.event_id, (participantCountByEvent.get(row.event_id) ?? 0) + 1);
  }
  const partialEntries =
    [...workMap.values()].filter((w) => w.eventIds.size < memberCount).length +
    [...participantMap.values()].filter((p) => p.eventIds.size < memberCount).length;
  const venues = [...new Set((members ?? []).map((m) => m.venues?.name).filter(Boolean))];
  const firstDate = members?.[0]?.start_datetime;
  const lastDate = members?.[members.length - 1]?.start_datetime;
  const roleSuggestions = [
    ...new Set([
      ...[...participantMap.values()].map((p) => p.roleLabel).filter((r): r is string => !!r),
      "Musikalische Leitung", "Inszenierung", "Dirigent:in", "Sopran", "Mezzosopran", "Alt", "Tenor", "Bariton", "Bass",
      "Violine", "Viola", "Violoncello", "Klavier", "Orchester", "Chor",
    ]),
  ];

  return (
    <div className="p-8">
      <Link href="/event-groups" className="text-sm text-neutral-500 hover:text-neutral-700">
        ← Zurück zu Event-Gruppen
      </Link>
      <div className="mt-2 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">{group.title}</h1>
          <p className="mt-1 text-sm text-neutral-500">
            {memberCount} Termin{memberCount === 1 ? "" : "e"}
            {firstDate && ` · ${formatDate(firstDate)}${lastDate && lastDate !== firstDate ? ` bis ${formatDate(lastDate)}` : ""}`}
            {venues.length > 0 && ` · ${venues.join(", ")}`}
          </p>
          <p className="mt-1 max-w-2xl text-xs text-neutral-500">
            Eine Eventgruppe bündelt die Termine einer Produktion. Programm und Besetzung pflegst du hier einmal;
            sie gelten für alle Termine, außer du schränkst einen Eintrag über „Termine bearbeiten“ ein.
          </p>
        </div>
        {partialEntries > 0 && memberCount > 1 && (
          <form action={alignGroupLineup.bind(null, id)} className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm">
            <p className="text-amber-800">
              {partialEntries} Eintr{partialEntries === 1 ? "ag gilt" : "äge gelten"} nur für einen Teil der Termine.
            </p>
            <div className="mt-2">
              <SubmitButton>Alles auf alle Termine übertragen</SubmitButton>
            </div>
          </form>
        )}
      </div>

      {/* 1. Termine */}
      <section className="mt-8">
        <h2 className="text-sm font-semibold text-neutral-900">1 · Termine</h2>
        <div className="mt-3 overflow-hidden rounded-lg border border-neutral-200 bg-white">
          {members?.length ? (
            <table className="w-full text-sm">
              <tbody>
                {members.map((e) => (
                  <tr key={e.id} className="border-t border-neutral-100 first:border-t-0">
                    <td className="whitespace-nowrap px-3 py-2">
                      <Link href={`/events/${e.id}`} className="font-medium text-neutral-900 hover:underline">
                        {formatDate(e.start_datetime)}
                      </Link>
                    </td>
                    <td className="px-3 py-2 text-neutral-600">{e.title}</td>
                    <td className="px-3 py-2 text-neutral-500">{e.venues?.name ?? "–"}</td>
                    <td className="whitespace-nowrap px-3 py-2 text-xs text-neutral-400">
                      {participantCountByEvent.get(e.id) ?? 0} Mitwirkende
                    </td>
                    <td className="px-3 py-2 text-right">
                      <DeleteButton
                        action={removeEventFromGroup.bind(null, id, e.id)}
                        confirmMessage="Diesen Termin aus der Gruppe entfernen? Das Event selbst bleibt erhalten."
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="px-3 py-6 text-center text-sm text-neutral-400">Keine Termine mehr in dieser Gruppe.</p>
          )}
        </div>
        <details className="mt-3" open={memberCount < 2}>
          <summary className="cursor-pointer text-sm font-medium text-[#2D2A6E]">+ Weitere Termine hinzufügen</summary>
          <div className="mt-3">
            <EventFinder groupId={id} />
          </div>
        </details>
      </section>

      <div className="mt-10 grid gap-10 lg:grid-cols-2">
        {/* 2. Besetzung */}
        <section>
          <h2 className="text-sm font-semibold text-neutral-900">2 · Besetzung ({participantMap.size})</h2>

          <ul className="mt-3 flex flex-col gap-2">
            {participantMap.size > 0 ? (
              Array.from(participantMap.entries()).map(([key, entry]) => (
                <li key={key} className="rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm">
                  <div className="flex items-center gap-2">
                    <span className="w-40 shrink-0 truncate font-medium text-neutral-900" title={entry.label}>{entry.label}</span>
                    <form action={setParticipantRoleInGroup.bind(null, id, entry.personId, entry.ensembleId)} className="flex min-w-0 flex-1 items-center gap-1">
                      <input
                        name="role_label"
                        defaultValue={entry.roleLabel ?? (entry.role ? ROLE_LABEL[entry.role] ?? entry.role : "")}
                        placeholder="Rolle"
                        list="group-role-suggestions"
                        maxLength={160}
                        aria-label={`Rolle von ${entry.label}`}
                        className="min-w-0 flex-1 border border-transparent bg-transparent px-1 py-0.5 text-sm text-neutral-600 hover:border-neutral-200 focus:border-neutral-300 focus:bg-white"
                      />
                      <button type="submit" className="text-xs text-neutral-400 hover:text-neutral-800">Speichern</button>
                    </form>
                    <DeleteButton
                      action={removeParticipantFromGroup.bind(null, id, entry.personId, entry.ensembleId)}
                      confirmMessage="Mitwirkende:n aus allen Terminen entfernen?"
                    />
                  </div>
                  <div className="mt-1 flex items-center gap-3">
                    {entry.eventIds.size < memberCount && (
                      <span className="text-[10px] font-medium uppercase text-amber-600">
                        nur {entry.eventIds.size}/{memberCount} Termine
                      </span>
                    )}
                    <MembershipEditor
                      events={checklistEvents}
                      checkedIds={new Set([...entry.eventIds].filter((eid) => allMemberIdsSet.has(eid)))}
                      onSave={setParticipantEventMembership.bind(null, id, entry.personId, entry.ensembleId, entry.roleLabel, entry.role)}
                    />
                  </div>
                </li>
              ))
            ) : (
              <li className="rounded-md border border-dashed border-neutral-300 px-3 py-6 text-center text-sm text-neutral-400">
                Noch keine Mitwirkenden erfasst.
              </li>
            )}
          </ul>
          <datalist id="group-role-suggestions">
            {roleSuggestions.map((label) => <option key={label} value={label} />)}
          </datalist>

          <div className="mt-6 flex flex-col gap-4">
            <ParticipantBulkAdder groupId={id} events={checklistEvents} roleSuggestions={roleSuggestions} />

            {memberCount > 1 && (
              <form action={copyLineupFromEvent.bind(null, id)} className="flex flex-col gap-2 rounded-lg border border-neutral-200 bg-white p-4">
                <p className="text-sm font-semibold text-neutral-900">Besetzung von einem Termin übernehmen</p>
                <p className="text-xs text-neutral-500">
                  Praktisch, wenn ein Termin schon vollständig importiert ist: dessen Besetzung kommt zu allen anderen Terminen.
                </p>
                <select name="source_event_id" required defaultValue="" className="border border-neutral-300 bg-white px-3 py-2 text-sm">
                  <option value="" disabled>Termin wählen …</option>
                  {(members ?? []).map((m) => (
                    <option key={m.id} value={m.id}>
                      {formatDate(m.start_datetime)} · {participantCountByEvent.get(m.id) ?? 0} Mitwirkende
                    </option>
                  ))}
                </select>
                <label className="flex items-center gap-2 text-xs text-neutral-600">
                  <input type="checkbox" name="with_works" defaultChecked />
                  Programm ebenfalls übernehmen
                </label>
                <SubmitButton>Übernehmen</SubmitButton>
              </form>
            )}

            <details className="rounded-lg border border-neutral-200 bg-white p-4">
              <summary className="cursor-pointer text-sm font-semibold text-neutral-900">Besetzung aus Text einlesen (KI)</summary>
              <div className="mt-3">
                <GroupParticipantImporter groupId={id} events={checklistEvents} checkedIds={allMemberIdsSet} />
              </div>
            </details>

            <details className="rounded-lg border border-neutral-200 bg-white p-4">
              <summary className="cursor-pointer text-sm font-semibold text-neutral-900">Neue Person oder neues Ensemble anlegen</summary>
              <div className="mt-3 flex flex-col gap-4">
                <form action={boundCreatePerson} className="flex flex-col gap-2">
                  <p className="text-xs font-medium text-neutral-600">Neue Person</p>
                  <TextInput name="full_name" placeholder="Vollständiger Name" required />
                  <TextInput name="role_label" placeholder="Rolle (optional)" maxLength={160} list="group-role-suggestions" />
                  <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
                  <SubmitButton>Anlegen & hinzufügen</SubmitButton>
                </form>
                <hr className="border-neutral-200" />
                <form action={boundCreateEnsemble} className="flex flex-col gap-2">
                  <p className="text-xs font-medium text-neutral-600">Neues Ensemble</p>
                  <TextInput name="name" placeholder="Name" required />
                  <TextInput name="role_label" placeholder="Funktion (optional)" maxLength={160} list="group-role-suggestions" />
                  <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
                  <SubmitButton>Anlegen & hinzufügen</SubmitButton>
                </form>
              </div>
            </details>
          </div>
        </section>

        {/* 3. Programm */}
        <section>
          <h2 className="text-sm font-semibold text-neutral-900">3 · Programm ({workMap.size})</h2>

          <ol className="mt-3 flex flex-col gap-2">
            {workMap.size > 0 ? (
              Array.from(workMap.entries()).map(([workId, entry], index, arr) => (
                <li key={workId} className="rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm">
                  <div className="flex items-center justify-between gap-3">
                    <MoveButtons
                      onMoveUp={moveWorkInGroup.bind(null, id, workId, "up")}
                      onMoveDown={moveWorkInGroup.bind(null, id, workId, "down")}
                      disableUp={index === 0}
                      disableDown={index === arr.length - 1}
                    />
                    <span className="flex-1">
                      {entry.afterIntermission && (
                        <span className="mr-2 rounded bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium uppercase text-amber-700">
                          nach Pause
                        </span>
                      )}
                      <span className="font-medium text-neutral-900">{entry.work?.title}</span>
                      {entry.work?.composer && <span className="text-neutral-500"> — {entry.work.composer.full_name}</span>}
                      {entry.work?.catalog_number && <span className="text-neutral-400"> ({entry.work.catalog_number})</span>}
                      {entry.eventIds.size < memberCount && (
                        <span className="ml-2 text-[10px] font-medium uppercase text-amber-600">
                          nur {entry.eventIds.size}/{memberCount} Termine
                        </span>
                      )}
                    </span>
                    <DeleteButton
                      action={removeWorkFromGroup.bind(null, id, workId)}
                      confirmMessage="Werk aus dem Programm aller Termine entfernen?"
                    />
                  </div>
                  <MembershipEditor
                    events={checklistEvents}
                    checkedIds={new Set([...entry.eventIds].filter((eid) => allMemberIdsSet.has(eid)))}
                    onSave={setWorkEventMembership.bind(null, id, workId)}
                  />
                </li>
              ))
            ) : (
              <li className="rounded-md border border-dashed border-neutral-300 px-3 py-6 text-center text-sm text-neutral-400">
                Noch keine Werke im Programm.
              </li>
            )}
          </ol>

          <div className="mt-6 flex flex-col gap-4 rounded-lg border border-neutral-200 bg-white p-4">
            <form action={boundAddExistingWork} className="flex flex-col gap-2">
              <p className="text-sm font-semibold text-neutral-900">Werk hinzufügen</p>
              <EntitySearch kind="work" name="work_id" placeholder="Werk suchen …" required />
              <label className="flex items-center gap-2 text-xs text-neutral-600">
                <input type="checkbox" name="after_intermission" />
                Nach der Pause
              </label>
              <details>
                <summary className="cursor-pointer text-xs font-medium text-neutral-500">Nur bei bestimmten Terminen …</summary>
                <div className="mt-2"><EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} /></div>
              </details>
              <SubmitButton>Hinzufügen</SubmitButton>
            </form>

            <details>
              <summary className="cursor-pointer text-xs font-medium text-neutral-600">Werk fehlt? Neu anlegen …</summary>
              <form action={boundCreateWorkAndAdd} className="mt-2 flex flex-col gap-2">
                <TextInput name="title" placeholder="Titel" required />
                <EntitySearch kind="person" name="composer_id" placeholder="Komponist:in suchen (optional) …" />
                <TextInput name="catalog_number" placeholder="Werkverzeichnis-Nr. (optional, z. B. BWV 244)" />
                <label className="flex items-center gap-2 text-xs text-neutral-600">
                  <input type="checkbox" name="after_intermission_new" />
                  Nach der Pause
                </label>
                <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
                <SubmitButton>Anlegen & hinzufügen</SubmitButton>
              </form>
            </details>
          </div>

          <div className="mt-8">
            <h2 className="text-sm font-semibold text-neutral-900">Bild</h2>
            <div className="mt-3">
              <GroupImageUploader
                groupId={id}
                currentImageUrl={groupImageUrl}
                coverage={groupImageCoverage}
                memberCount={memberCount}
              />
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
