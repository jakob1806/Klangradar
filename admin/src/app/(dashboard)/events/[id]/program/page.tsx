import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Field, Select, TextInput } from "@/components/form-fields";
import { SubmitButton } from "@/components/submit-button";
import { DeleteButton } from "@/components/delete-button";
import {
  addExistingWork,
  addParticipant,
  createWorkAndAdd,
  moveWork,
  removeParticipant,
  removeWork,
} from "./actions";
import { MoveButtons } from "./move-buttons";

const ROLE_LABEL: Record<string, string> = {
  komponist: "Komponist:in",
  dirigent: "Dirigent:in",
  solist: "Solist:in",
  chorleiter: "Chorleiter:in",
  moderator: "Moderator:in",
};

interface ProgramWorkRow {
  work_id: string;
  position: number;
  after_intermission: boolean;
  works: { title: string; catalog_number: string | null; composer: { full_name: string } | null } | null;
}

interface ParticipantRow {
  id: string;
  role: string | null;
  persons: { full_name: string } | null;
  ensembles: { name: string } | null;
}

export default async function EventProgramPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [
    { data: event },
    { data: program },
    { data: participants },
    { data: works },
    { data: persons },
    { data: ensembles },
  ] = await Promise.all([
    supabase.from("events").select("id, title").eq("id", id).maybeSingle(),
    supabase
      .from("event_works")
      .select("work_id, position, after_intermission, works(title, catalog_number, composer:persons(full_name))")
      .eq("event_id", id)
      .order("position")
      .returns<ProgramWorkRow[]>(),
    supabase
      .from("event_participants")
      .select("id, role, persons(full_name), ensembles(name)")
      .eq("event_id", id)
      .returns<ParticipantRow[]>(),
    supabase
      .from("works")
      .select("id, title, composer:persons(full_name)")
      .order("title")
      .returns<{ id: string; title: string; composer: { full_name: string } | null }[]>(),
    supabase.from("persons").select("id, full_name").order("full_name"),
    supabase.from("ensembles").select("id, name").order("name"),
  ]);

  if (!event) notFound();

  const boundAddExistingWork = addExistingWork.bind(null, id);
  const boundCreateWorkAndAdd = createWorkAndAdd.bind(null, id);
  const boundAddParticipant = addParticipant.bind(null, id);

  return (
    <div className="p-8">
      <Link href={`/events/${id}`} className="text-sm text-neutral-500 hover:text-neutral-700">
        ← Zurück zu {event.title}
      </Link>
      <h1 className="mt-2 text-xl font-semibold tracking-tight">Programm & Mitwirkende</h1>

      <div className="mt-8 grid gap-10 lg:grid-cols-2">
        {/* Programm */}
        <section>
          <h2 className="text-sm font-semibold text-neutral-900">Programm</h2>

          <ol className="mt-3 flex flex-col gap-2">
            {program?.length ? (
              program.map((row, index) => (
                <li
                  key={`${row.work_id}-${row.position}`}
                  className="flex items-center justify-between gap-3 rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm"
                >
                  <MoveButtons
                    onMoveUp={moveWork.bind(null, id, row.work_id, row.position, "up")}
                    onMoveDown={moveWork.bind(null, id, row.work_id, row.position, "down")}
                    disableUp={index === 0}
                    disableDown={index === program.length - 1}
                  />
                  <span className="flex-1">
                    {row.after_intermission && (
                      <span className="mr-2 rounded bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium uppercase text-amber-700">
                        nach Pause
                      </span>
                    )}
                    <span className="font-medium text-neutral-900">{row.works?.title}</span>
                    {row.works?.composer && (
                      <span className="text-neutral-500"> — {row.works.composer.full_name}</span>
                    )}
                    {row.works?.catalog_number && (
                      <span className="text-neutral-400"> ({row.works.catalog_number})</span>
                    )}
                  </span>
                  <DeleteButton
                    action={removeWork.bind(null, id, row.work_id, row.position)}
                    confirmMessage="Werk aus dem Programm entfernen?"
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
              <SubmitButton>Anlegen & hinzufügen</SubmitButton>
            </form>
          </div>
        </section>

        {/* Mitwirkende */}
        <section>
          <h2 className="text-sm font-semibold text-neutral-900">Mitwirkende</h2>

          <ul className="mt-3 flex flex-col gap-2">
            {participants?.length ? (
              participants.map((p) => (
                <li
                  key={p.id}
                  className="flex items-center justify-between rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm"
                >
                  <span>
                    <span className="font-medium text-neutral-900">
                      {p.persons?.full_name ?? p.ensembles?.name}
                    </span>
                    {p.role && (
                      <span className="text-neutral-500"> — {ROLE_LABEL[p.role] ?? p.role}</span>
                    )}
                  </span>
                  <DeleteButton
                    action={removeParticipant.bind(null, id, p.id)}
                    confirmMessage="Mitwirkende:n entfernen?"
                  />
                </li>
              ))
            ) : (
              <li className="rounded-md border border-dashed border-neutral-300 px-3 py-6 text-center text-sm text-neutral-400">
                Noch keine Mitwirkenden erfasst.
              </li>
            )}
          </ul>

          <div className="mt-6 flex flex-col gap-4 rounded-lg border border-neutral-200 bg-white p-4">
            <form action={boundAddParticipant} className="flex flex-col gap-2">
              <p className="text-xs font-medium text-neutral-600">Person hinzufügen</p>
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
              <Select name="role" defaultValue="">
                <option value="">Rolle (optional)</option>
                {Object.entries(ROLE_LABEL).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </Select>
              <SubmitButton>Hinzufügen</SubmitButton>
            </form>

            <hr className="border-neutral-200" />

            <form action={boundAddParticipant} className="flex flex-col gap-2">
              <p className="text-xs font-medium text-neutral-600">Ensemble hinzufügen</p>
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
              <SubmitButton>Hinzufügen</SubmitButton>
            </form>
          </div>
        </section>
      </div>
    </div>
  );
}
