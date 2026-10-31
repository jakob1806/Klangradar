-- Erstellt von Claude Code (Nutzerwunsch 31.10.2026: Programm treffsicherer,
-- keine doppelten Werke, Pause als eigener Punkt).
--
-- Befund (kommende Termine): 42 Konzerte mit demselben Werk mehrfach im
-- Programm (Musikverein: Ouvertüre bis zu 4×), Zeilen alter Erkennungen
-- blieben neben neuen stehen (gleiche Position, zwei Werke), 191 Konzerte
-- "mit Pause" ohne Pausenmarkierung im Programm.
--
-- 1. events.program_locked_at: wird gesetzt, sobald die Redaktion das
--    Programm im Admin ändert (Trigger auf event_works, nur für angemeldete
--    Redaktion). Automatische Erkennung überschreibt solche Programme nicht.
-- 2. replace_event_program(): ersetzt das Programm eines Termins als Ganzes,
--    entfernt doppelte Werke je Programmhälfte und nummeriert neu.
-- 3. Einmalige Bereinigung bestehender Dubletten.
-- 4. Konzerte "mit Pause", aber ohne Pausenmarkierung, sowie Konzerte mit
--    Dubletten werden neu erkannt (außer redaktionell gesperrten und den
--    Quellen mit eigenem Detail-Abgleich, die ihr Programm selbst schreiben).

set statement_timeout = '10min';

alter table public.events add column if not exists program_locked_at timestamptz;

create or replace function public.mark_program_edited()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and is_admin_or_editor() then
    update events set program_locked_at = now()
     where id = coalesce(new.event_id, old.event_id) and program_locked_at is null;
  end if;
  return null;
end;
$$;
drop trigger if exists mark_program_edited on public.event_works;
create trigger mark_program_edited after insert or update or delete on public.event_works
  for each row execute function public.mark_program_edited();

create or replace function public.replace_event_program(p_event_id uuid, p_links jsonb)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from events where id = p_event_id and program_locked_at is not null) then
    return false;
  end if;
  delete from event_works where event_id = p_event_id;
  insert into event_works (event_id, work_id, position, after_intermission)
  select p_event_id, d.work_id,
    (row_number() over (order by d.after_intermission, d.position) - 1)::int,
    d.after_intermission
  from (
    -- Gleiches Werk in derselben Programmhälfte nur einmal (erste Stelle).
    select distinct on (l.work_id, l.after_intermission) l.work_id, l.position, l.after_intermission
    from jsonb_to_recordset(coalesce(p_links, '[]'::jsonb)) as l(work_id uuid, position int, after_intermission boolean)
    where l.work_id is not null
    order by l.work_id, l.after_intermission, l.position
  ) d;
  return true;
end;
$$;
revoke all on function public.replace_event_program(uuid, jsonb) from public, anon, authenticated;

-- 3a. Gleiches Werk mehrfach in derselben Programmhälfte: erste Stelle behalten.
delete from public.event_works ew
using (
  select event_id, work_id, after_intermission, min(position) keep_position
  from public.event_works
  group by event_id, work_id, after_intermission
  having count(*) > 1
) d
where ew.event_id = d.event_id and ew.work_id = d.work_id
  and ew.after_intermission = d.after_intermission and ew.position > d.keep_position;

-- 3b. Zwei Werke derselben Komponist:in an derselben Position (Rest einer
--     früheren Erkennung): das in mehr Programmen verwendete Werk behalten.
delete from public.event_works ew
using (
  select ew2.event_id, ew2.position, ew2.work_id,
    row_number() over (
      partition by ew2.event_id, ew2.position, w.composer_id
      order by (select count(*) from public.event_works x where x.work_id = ew2.work_id) desc, ew2.work_id
    ) rn
  from public.event_works ew2
  join public.works w on w.id = ew2.work_id
  where w.composer_id is not null
) r
where ew.event_id = r.event_id and ew.position = r.position and ew.work_id = r.work_id and r.rn > 1;

-- 4. Neu erkennen lassen.
update public.events e
   set program_extraction_status = 'pending', program_retry_after = null
 where e.start_datetime >= now()
   and e.status = 'scheduled'
   and e.program_locked_at is null
   and coalesce(e.website_url, '') !~* '(staatsoper\.de|musikverein\.at|mphil\.de|wienerphilharmoniker\.at)'
   and e.has_intermission
   and exists (select 1 from public.event_works ew where ew.event_id = e.id)
   and not exists (select 1 from public.event_works ew where ew.event_id = e.id and ew.after_intermission);

-- Musikverein-Termine, deren Programm Dubletten hatte, im Detail-Abgleich
-- neu laden (schreibt jetzt über replace_event_program).
update public.events
   set musikverein_detail_synced_at = null
 where start_datetime >= now() and website_url ilike '%musikverein.at%';
