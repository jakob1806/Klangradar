-- Erstellt von Claude Code (18.11.2026): Werke aufräumen.
-- 1. Exakte Duplikate (gleicher Komponist, gleicher Titel ohne Groß-/Klein-
--    schreibung und Leerzeichen-Unterschiede, kein abweichendes Werkverzeichnis)
--    zusammenführen – z. B. 138× „Konzert in F für Klavier und Orchester“.
-- 2. Schreibweisen vereinheitlichen: Tonarten „d-Moll“/„A-Dur“, leere Tonart
--    und „null“-Werkverzeichnis entfernen, „Konzert for“ → „Konzert für“,
--    „Konzert grosso“ → „Concerto grosso“.
-- 3. Offensichtliche Fehleinträge entfernen, die keine Werke sind
--    („Werke von …“, Veranstaltungstitel „… in Concert“, „… Live 2027“,
--    Zeichensalat mit „??“).

-- 1. Duplikate
do $$
declare r record;
begin
  for r in
    with norm as (
      select id, composer_id, created_at,
             lower(regexp_replace(btrim(title), '\s+', ' ', 'g')) as t,
             nullif(lower(regexp_replace(coalesce(catalog_number, ''), '\s+', '', 'g')), '') as cat
      from works
    ),
    grouped as (
      select id, first_value(id) over (partition by composer_id, t order by created_at, id) as keep_id, cat,
             first_value(cat) over (partition by composer_id, t order by created_at, id) as keep_cat
      from norm
    )
    select id, keep_id from grouped
    where id <> keep_id and (cat is null or keep_cat is null or cat = keep_cat)
  loop
    begin
      perform merge_works(r.keep_id, r.id);
    exception when others then
      raise warning 'merge_works % -> %: %', r.id, r.keep_id, sqlerrm;
    end;
  end loop;
end $$;

-- 2. Schreibweisen
update works set key_signature = null where key_signature is not null and btrim(key_signature) = '';
update works set catalog_number = null where catalog_number is not null and lower(btrim(catalog_number)) in ('', 'null', 'none');
update works set key_signature = regexp_replace(regexp_replace(key_signature, '-moll\M', '-Moll', 'g'), '-dur\M', '-Dur', 'g')
  where key_signature ~ '-(moll|dur)\M';
update works set title = regexp_replace(regexp_replace(title, '\m([A-Ha-h](is|es|s)?)-moll\M', '\1-Moll', 'g'), '\m([A-Ha-h](is|es|s)?)-dur\M', '\1-Dur', 'g')
  where title ~ '\m[A-Ha-h](is|es|s)?-(moll|dur)\M';
update works set title = regexp_replace(title, '^Konzert for ', 'Konzert für ') where title ~ '^Konzert for ';
update works set title = regexp_replace(title, '^Konzert grosso', 'Concerto grosso') where title ~ '^Konzert grosso';

-- 3. Fehleinträge (nur wenn niemand sie als Lieblingswerk hat)
with junk as (
  select w.id from works w
  where (w.title ~* '^Werke von '
      or w.title ~ '\?\?'
      or w.title ~* '(\s[–-]\s|\s)in Concert$'
      or w.title ~* '[–-]\s*Live 20\d\d$')
    and not exists (select 1 from user_favorite_works f where f.work_id = w.id)
)
delete from event_works where work_id in (select id from junk);
do $$
declare r record;
begin
  for r in select w.id from works w
    where (w.title ~* '^Werke von ' or w.title ~ '\?\?' or w.title ~* '(\s[–-]\s|\s)in Concert$' or w.title ~* '[–-]\s*Live 20\d\d$')
      and not exists (select 1 from user_favorite_works f where f.work_id = w.id)
      and not exists (select 1 from event_works ew where ew.work_id = w.id)
  loop
    begin
      delete from works where id = r.id;
    exception when foreign_key_violation then
      null; -- noch anderweitig verknüpft: stehen lassen
    end;
  end loop;
end $$;
