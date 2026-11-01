-- Erstellt von Claude Code (01.11.2026): Bereinigung unsinniger
-- Personeneinträge. Die Bildprüfung (Migration 000148) hat Personen wie
-- „Volkslied“, „Komparserie“ oder „Napoleon“ (Bühnenfigur) aufgedeckt. Sie
-- entstehen, wenn Programmzeilen Gattungsbegriffe statt Namen enthalten.
--
-- 1. public.is_non_person_name: dieselbe Begriffsliste wie
--    functions/_shared/entityNameValidation.ts (NON_PERSON_NAMES) – beide
--    gleich halten. Die Edge Functions legen solche Personen nicht mehr an.
-- 2. Einmalige Bereinigung: nur unbestätigte Personen (is_verified = false).
--    Verknüpfungen zu Konzerten werden gelöst, Werke verlieren die falsche
--    Komponist:in, dann wird die Person gelöscht. Hängt sie noch woanders
--    (z. B. ein Fremdschlüssel ohne Cascade), bleibt sie stehen und wird nur
--    protokolliert. Alles landet in system_logs (action 'non_person_cleanup').

create or replace function public.is_non_person_name(p_name text)
returns boolean
language sql
immutable
as $$
  select trim(regexp_replace(
           regexp_replace(
             translate(lower(coalesce(p_name, '')),
               'äöüßáàâãåéèêëíìîïóòôõúùûýñç',
               'aousaaaaaeeeeiiiiooooouuuync'),
             '[^a-z0-9]+', ' ', 'g'),
           '\s+', ' ', 'g'))
         = any (array[
    'volkslied', 'volksweise', 'traditional', 'traditionell', 'trad', 'anonym', 'anonymus', 'anonymous',
    'unbekannt', 'unknown', 'nn', 'n n', 'tba', 'tbd', 'diverse', 'verschiedene', 'various', 'various artists',
    'komparserie', 'statisterie', 'kinderstatisterie', 'extrachor', 'zusatzchor', 'kinderchor', 'chor',
    'orchester', 'ensemble', 'solisten', 'ballett', 'tanz', 'band', 'dj', 'gaste', 'gast', 'special guest',
    'uberraschungsgast', 'moderation', 'lesung', 'sprecher', 'erzahler', 'napoleon', 'gregorianik',
    'gregorianischer choral', 'spiritual', 'gospel', 'choral', 'kirchenlied', 'weihnachtslied'
  ]);
$$;

do $$
declare
  r record;
  v_links int;
  v_works int;
begin
  for r in
    select id, full_name, slug from public.persons
    where coalesce(is_verified, false) = false
      and public.is_non_person_name(full_name)
  loop
    delete from public.event_participants where person_id = r.id;
    get diagnostics v_links = row_count;
    update public.works set composer_id = null where composer_id = r.id;
    get diagnostics v_works = row_count;
    begin
      delete from public.persons where id = r.id;
      insert into public.system_logs (entity_type, entity_id, action, actor, before, after)
      values ('person', r.id, 'non_person_cleanup', 'system',
              jsonb_build_object('full_name', r.full_name, 'slug', r.slug),
              jsonb_build_object('deleted', true, 'event_links_removed', v_links, 'works_unlinked', v_works));
    exception when foreign_key_violation then
      insert into public.system_logs (entity_type, entity_id, action, actor, before, after)
      values ('person', r.id, 'non_person_cleanup', 'system',
              jsonb_build_object('full_name', r.full_name, 'slug', r.slug),
              jsonb_build_object('deleted', false, 'reason', sqlerrm, 'event_links_removed', v_links, 'works_unlinked', v_works));
    end;
  end loop;
end;
$$;
