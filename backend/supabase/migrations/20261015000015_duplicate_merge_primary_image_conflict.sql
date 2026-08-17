-- Verhindert den Fehler "images_one_primary_per_origin_idx" beim atomaren
-- Zusammenfuehren von Personen und Ensembles. Beide Datensaetze duerfen vor
-- dem Merge je ein Primaerbild haben, danach aber nur noch eines.

create or replace function public.prepare_duplicate_image_merge(
  p_origin_type text,
  p_keep_origin_id uuid,
  p_remove_origin_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_origin_type not in ('person', 'ensemble') then
    raise exception 'Nicht unterstuetzter Bild-Entitaetstyp: %', p_origin_type;
  end if;

  -- Nur wenn das Ziel schon ein Primaerbild hat, verliert das Primaerbild
  -- der zu entfernenden Version seinen Status. Alle Bilder bleiben erhalten.
  update images
  set is_primary = false
  where origin_type = p_origin_type
    and origin_id = p_remove_origin_id
    and is_primary
    and exists (
      select 1 from images
      where origin_type = p_origin_type
        and origin_id = p_keep_origin_id
        and is_primary
    );
end;
$$;

revoke all on function public.prepare_duplicate_image_merge(text,uuid,uuid) from public;

-- Die bereits produktiv vorhandenen atomaren Merge-Funktionen werden
-- gezielt um den Vorbereitungsschritt erweitert. pg_get_functiondef haelt
-- dabei die vollstaendige, aktuelle Funktionsimplementierung bei und macht
-- die Migration auch gegen weitere additive Felder robust.
do $$
declare
  function_definition text;
  old_statement text;
  new_statement text;
begin
  select pg_get_functiondef('public.merge_person_duplicate_candidate(uuid,uuid)'::regprocedure)
    into function_definition;
  old_statement := 'update images set origin_id=p_keep_person_id where origin_type=''person'' and origin_id=remove_id;';
  new_statement := 'perform public.prepare_duplicate_image_merge(''person'', p_keep_person_id, remove_id);' || chr(10) || '  ' || old_statement;
  if position(old_statement in function_definition) = 0 then
    raise exception 'Bild-Merge-Stelle in merge_person_duplicate_candidate nicht gefunden';
  end if;
  execute replace(function_definition, old_statement, new_statement);

  select pg_get_functiondef('public.merge_ensemble_duplicate_candidate(uuid,uuid)'::regprocedure)
    into function_definition;
  old_statement := 'update images set origin_id=p_keep_ensemble_id where origin_type=''ensemble'' and origin_id=remove_id;';
  new_statement := 'perform public.prepare_duplicate_image_merge(''ensemble'', p_keep_ensemble_id, remove_id);' || chr(10) || '  ' || old_statement;
  if position(old_statement in function_definition) = 0 then
    raise exception 'Bild-Merge-Stelle in merge_ensemble_duplicate_candidate nicht gefunden';
  end if;
  execute replace(function_definition, old_statement, new_statement);
end;
$$;
