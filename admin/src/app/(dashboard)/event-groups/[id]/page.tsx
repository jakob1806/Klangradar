import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Field, Select, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { DeleteButton } from "@/components/delete-button";
import { removeEventFromGroup } from "../actions";
import { EventChecklist } from "./event-checklist";
import { GroupImageUploader } from "./group-image-uploader";
import { GroupParticipantImporter } from "./group-participant-importer";
import { MembershipEditor } from "./membership-editor";
import { MoveButtons } from "../../events/[id]/program/move-buttons";
import { formatMunichDateTime } from "@/lib/munich-time";
import {
  addExistingWorkToGroup,
  addParticipantToGroup,
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

  const [{ data: workRows }, { data: participantRows }, { data: works }, { data: persons }, { data: ensembles }, { data: ungrouped }] =
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
          supabase
            .from("works")
            .select("id, title, composer:persons(full_name)")
            .order("title")
            .returns<{ id: string; title: string; composer: { full_name: string } | null }[]>(),
          supabase.from("persons").select("id, full_name").order("full_name"),
          supabase.from("ensembles").select("id, name").eq("is_resolution_placeholder", false).eq("is_family_root", false).order("name"),
          supabase
            .from("events")
            .select("id, title, start_datetime")
            .is("program_id", null)
            .order("start_datetime", { ascending: true })
            .returns<{ id: string; title: string; start_datetime: string }[]>(),
        ])
      : [{ data: [] }, { data: [] }, { data: [] }, { data: [] }, { data: [] }, { data: [] }];

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
  const boundAddParticipant = addParticipantToGroup.bind(null, id);
  const boundCreatePerson = createPersonAndAddToGroup.bind(null, id);
  const boundCreateEnsemble = createEnsembleAndAddToGroup.bind(null, id);

  return (
    <div className="p-8">
      <Link href="/event-groups" className="text-sm text-neutral-500 hover:text-neutral-700">
        ← Zurück zu Event-Gruppen
      </Link>
      <h1 className="mt-2 text-xl font-semibold tracking-tight">{group.title}</h1>
      <p className="mt-1 text-sm text-neutral-500">
        Änderungen an Programm &amp; Mitwirkenden gelten standardmäßig für alle {memberCount} Termine dieser Gruppe —
        beim Hinzufügen und über „Termine bearbeiten“ pro Eintrag kann das auf einzelne Termine eingeschränkt werden.
      </p>

      <div className="mt-4">
        <GroupImageUploader
          groupId={id}
          currentImageUrl={groupImageUrl}
          coverage={groupImageCoverage}
          memberCount={memberCount}
        />
      </div>

      <section className="mt-8">
        <h2 className="text-sm font-semibold text-neutral-900">Termine ({memberCount})</h2>
        <ul className="mt-3 flex flex-col gap-2">
          {members?.length ? (
            members.map((e) => (
              <li
                key={e.id}
                className="flex items-center justify-between rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm"
              >
                <span>
                  <Link href={`/events/${e.id}`} className="font-medium text-neutral-900 hover:underline">
                    {formatDate(e.start_datetime)}
                  </Link>
                  {e.venues?.name && <span className="text-neutral-400"> · {e.venues.name}</span>}
                </span>
                <DeleteButton
                  action={removeEventFromGroup.bind(null, id, e.id)}
                  confirmMessage="Diesen Termin aus der Gruppe entfernen? Das Event selbst bleibt erhalten."
                />
              </li>
            ))
          ) : (
            <li className="rounded-md border border-dashed border-neutral-300 px-3 py-6 text-center text-sm text-neutral-400">
              Keine Termine mehr in dieser Gruppe.
            </li>
          )}
        </ul>

        {ungrouped && ungrouped.length > 0 && (
          <form action={async (formData: FormData) => {
            "use server";
            const { addEventToGroup } = await import("../actions");
            const eventId = String(formData.get("event_id") ?? "");
            await addEventToGroup(id, eventId);
          }} className="mt-3 flex items-end gap-2">
            <div className="flex-1">
              <Field label="Weiteren Termin hinzufügen">
                <Select name="event_id" required defaultValue="">
                  <option value="" disabled>
                    Event wählen…
                  </option>
                  {ungrouped.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.title} — {formatDate(e.start_datetime)}
                    </option>
                  ))}
                </Select>
              </Field>
            </div>
            <SubmitButton>Hinzufügen</SubmitButton>
          </form>
        )}
      </section>

      <div className="mt-10 grid gap-10 lg:grid-cols-2">
        {/* Programm */}
        <section>
          <h2 className="text-sm font-semibold text-neutral-900">Programm</h2>

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
                      {entry.work?.composer && (
                        <span className="text-neutral-500"> — {entry.work.composer.full_name}</span>
                      )}
                      {entry.work?.catalog_number && (
                        <span className="text-neutral-400"> ({entry.work.catalog_number})</span>
                      )}
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
              <Field label="Vorhandenes Werk hinzufügen">
                <Select name="work_id" required defaultValue="">
                  <option value="" disabled>
                    Werk wählen…
                  </option>
                  {works?.map((w) => (
                    <option key={w.id} value={w.id}>
                      {w.title}
                      {w.composer ? ` — ${w.composer.full_name}` : ""}
                    </option>
                  ))}
                </Select>
              </Field>
              <label className="flex items-center gap-2 text-xs text-neutral-600">
                <input type="checkbox" name="after_intermission" />
                Nach der Pause
              </label>
              <p className="text-xs font-medium text-neutral-500">Bei welchen Terminen?</p>
              <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
              <SubmitButton>Hinzufügen</SubmitButton>
            </form>

            <hr className="border-neutral-200" />

            <form action={boundCreateWorkAndAdd} className="flex flex-col gap-2">
              <p className="text-xs font-medium text-neutral-600">Neues Werk anlegen & hinzufügen</p>
              <TextInput name="title" placeholder="Titel" required />
              <Select name="composer_id" defaultValue="">
                <option value="">Komponist:in (optional)</option>
                {persons?.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.full_name}
                  </option>
                ))}
              </Select>
              <TextInput name="catalog_number" placeholder="Werkverzeichnis-Nr. (optional, z. B. BWV 244)" />
              <label className="flex items-center gap-2 text-xs text-neutral-600">
                <input type="checkbox" name="after_intermission_new" />
                Nach der Pause
              </label>
              <p className="text-xs font-medium text-neutral-500">Bei welchen Terminen?</p>
              <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
              <SubmitButton>Anlegen & hinzufügen</SubmitButton>
            </form>
          </div>
        </section>

        {/* Mitwirkende */}
        <section>
          <h2 className="text-sm font-semibold text-neutral-900">Mitwirkende</h2>

          <ul className="mt-3 flex flex-col gap-2">
            {participantMap.size > 0 ? (
              Array.from(participantMap.entries()).map(([key, entry]) => (
                <li key={key} className="rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm">
                  <div className="flex items-center justify-between">
                    <span>
                      <span className="font-medium text-neutral-900">{entry.label}</span>
                      {(entry.roleLabel || entry.role) && <span className="text-neutral-500"> — {entry.roleLabel ?? ROLE_LABEL[entry.role!] ?? entry.role}</span>}
                      {entry.eventIds.size < memberCount && (
                        <span className="ml-2 text-[10px] font-medium uppercase text-amber-600">
                          nur {entry.eventIds.size}/{memberCount} Termine
                        </span>
                      )}
                    </span>
                    <DeleteButton
                      action={removeParticipantFromGroup.bind(null, id, entry.personId, entry.ensembleId)}
                      confirmMessage="Mitwirkende:n aus allen Terminen entfernen?"
                    />
                  </div>
                  <MembershipEditor
                    events={checklistEvents}
                    checkedIds={new Set([...entry.eventIds].filter((eid) => allMemberIdsSet.has(eid)))}
                    onSave={setParticipantEventMembership.bind(null, id, entry.personId, entry.ensembleId, entry.roleLabel, entry.role)}
                  />
                </li>
              ))
            ) : (
              <li className="rounded-md border border-dashed border-neutral-300 px-3 py-6 text-center text-sm text-neutral-400">
                Noch keine Mitwirkenden erfasst.
              </li>
            )}
          </ul>

          <div className="mt-6">
            <GroupParticipantImporter groupId={id} events={checklistEvents} checkedIds={allMemberIdsSet} />
          </div>

          <div className="mt-6 flex flex-col gap-4 rounded-lg border border-neutral-200 bg-white p-4">
            <form action={boundAddParticipant} className="flex flex-col gap-2">
              <p className="text-xs font-medium text-neutral-600">Vorhandene Person hinzufügen</p>
              <Select name="person_id" required defaultValue="">
                <option value="" disabled>
                  Person wählen…
                </option>
                {persons?.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.full_name}
                  </option>
                ))}
              </Select>
              <TextInput name="role_label" placeholder="Rolle (frei, z. B. Lady Macbeth oder Basssolist)" maxLength={160} list="group-role-suggestions" />
              <p className="text-xs font-medium text-neutral-500">Bei welchen Terminen?</p>
              <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
              <SubmitButton>Hinzufügen</SubmitButton>
            </form>

            <hr className="border-neutral-200" />

            <form action={boundCreatePerson} className="flex flex-col gap-2">
              <p className="text-xs font-medium text-neutral-600">Neue Person anlegen & hinzufügen</p>
              <TextInput name="full_name" placeholder="Vollständiger Name" required />
              <TextInput name="role_label" placeholder="Rolle (frei, optional)" maxLength={160} list="group-role-suggestions" />
              <p className="text-xs font-medium text-neutral-500">Bei welchen Terminen?</p>
              <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
              <SubmitButton>Anlegen & hinzufügen</SubmitButton>
            </form>

            <hr className="border-neutral-200" />

            <form action={boundAddParticipant} className="flex flex-col gap-2">
              <p className="text-xs font-medium text-neutral-600">Vorhandenes Ensemble hinzufügen</p>
              <Select name="ensemble_id" required defaultValue="">
                <option value="" disabled>
                  Ensemble wählen…
                </option>
                {ensembles?.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.name}
                  </option>
                ))}
              </Select>
              <TextInput name="role_label" placeholder="Rolle/Funktion (frei, optional)" maxLength={160} list="group-role-suggestions" />
              <p className="text-xs font-medium text-neutral-500">Bei welchen Terminen?</p>
              <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
              <SubmitButton>Hinzufügen</SubmitButton>
            </form>

            <hr className="border-neutral-200" />

            <form action={boundCreateEnsemble} className="flex flex-col gap-2">
              <p className="text-xs font-medium text-neutral-600">Neues Ensemble anlegen & hinzufügen</p>
              <TextInput name="name" placeholder="Name" required />
              <TextInput name="role_label" placeholder="Rolle/Funktion (frei, optional)" maxLength={160} list="group-role-suggestions" />
              <p className="text-xs font-medium text-neutral-500">Bei welchen Terminen?</p>
              <EventChecklist events={checklistEvents} checkedIds={allMemberIdsSet} />
              <SubmitButton>Anlegen & hinzufügen</SubmitButton>
            </form>
            <datalist id="group-role-suggestions">
              {Object.values(ROLE_LABEL).map((label) => <option key={label} value={label} />)}
              <option value="Sopran" />
              <option value="Tenor" />
              <option value="Bass" />
              <option value="Violine" />
              <option value="Klavier" />
              <option value="Musikalische Leitung" />
            </datalist>
          </div>
        </section>
      </div>
    </div>
  );
}
