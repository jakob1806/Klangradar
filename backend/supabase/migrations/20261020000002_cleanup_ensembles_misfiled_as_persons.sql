-- Datenbereinigung für den Staatsoper-Scraper-Bug (siehe
-- backend/supabase/functions/_shared/staatsoperDetail.ts,
-- parseStaatsoperDetail): verlinkte Ensemble-Namen unter einer
-- Rollen-Überschrift wie "**Chor**" wurden bislang immer als "person"
-- klassifiziert, weil dort keine Ensemble-Namensprüfung lief. Konkret
-- betroffen: "Tölzer Knabenchor" als eigener persons-Datensatz statt
-- Auflösung auf den bestehenden ensembles-Datensatz (siehe
-- 20260817000002_import_excel_stammdaten.sql).
--
-- Diese Migration findet JEDE persons-Zeile, deren Name exakt (nach
-- normalize_entity_name) einem existierenden Ensemble-Namen oder
-- -Alias entspricht — nicht nur Tölzer Knabenchor — und hängt alle
-- Verweise auf den echten Ensemble-Datensatz um, bevor die
-- fehlerhafte Personen-Zeile gelöscht wird. Folgt demselben Muster
-- wie merge_person_duplicate_candidate() in
-- 20261014000001_atomic_duplicate_merges_user_delete_and_location.sql,
-- nur typübergreifend (person -> ensemble statt person -> person).

do $$
declare
  pair record;
  remove_id uuid;
  keep_id uuid;
  remove_name text;
begin
  for pair in
    select distinct p.id as person_id, p.full_name, coalesce(canon.id, alias.entity_id) as ensemble_id
    from persons p
    left join ensembles canon
      on public.normalize_entity_name(canon.name) = public.normalize_entity_name(p.full_name)
    left join entity_aliases alias
      on alias.entity_type = 'ensemble'
      and alias.alias_normalized = public.normalize_entity_name(p.full_name)
    where canon.id is not null or alias.entity_id is not null
  loop
    remove_id := pair.person_id;
    keep_id := pair.ensemble_id;
    remove_name := pair.full_name;

    raise notice 'Bereinige fälschlich als Person angelegtes Ensemble: % (person %) -> ensemble %', remove_name, remove_id, keep_id;

    -- event_participants: erst Kollisionen wegräumen (unique index
    -- event_participants_event_ensemble_uniq greift sonst beim Umhängen),
    -- dann person_id durch ensemble_id ersetzen.
    delete from event_participants old
      where old.person_id = remove_id and exists (
        select 1 from event_participants kept
        where kept.event_id = old.event_id and kept.ensemble_id = keep_id
      );
    update event_participants set person_id = null, ensemble_id = keep_id where person_id = remove_id;

    -- Werke/Quellen/Kandidaten, die fälschlich auf die Person statt das
    -- Ensemble zeigen, gibt es für einen Chor praktisch nie (composer_id
    -- etc. sind personenspezifisch) — trotzdem sicherheitshalber leeren,
    -- damit keine verwaiste FK auf die gleich gelöschte Zeile stehen bleibt.
    update works set composer_id = null where composer_id = remove_id;
    update sources set person_id = null where person_id = remove_id;
    update entity_candidates set created_person_id = null where created_person_id = remove_id;

    -- Bilder: Galerie-Bilder der Person werden Galerie-Bilder des Ensembles;
    -- ein bereits vorhandenes primäres Ensemble-Bild hat Vorrang.
    update images set is_primary = false
      where origin_type = 'person' and origin_id = remove_id and is_primary
        and exists (select 1 from images where origin_type = 'ensemble' and origin_id = keep_id and is_primary);
    update images set origin_type = 'ensemble', origin_id = keep_id where origin_type = 'person' and origin_id = remove_id;

    -- Provenienz-Einträge: nur übernehmen, wenn das Ensemble das Feld noch
    -- nicht hat, sonst verwaist die Zeile beim Löschen der Person.
    delete from field_provenance old where old.entity_type = 'person' and old.entity_id = remove_id and exists (
      select 1 from field_provenance kept where kept.entity_type = 'ensemble' and kept.entity_id = keep_id and kept.field_name = old.field_name
    );
    update field_provenance set entity_type = 'ensemble', entity_id = keep_id where entity_type = 'person' and entity_id = remove_id;

    -- Aliasse der fehlerhaften Person auf das Ensemble umhängen, Dubletten
    -- verwerfen; den alten Personennamen selbst als Alias sichern, falls er
    -- vom kanonischen Ensemble-Namen abweicht (z.B. Tippfehler-Varianten).
    delete from entity_aliases old where old.entity_type = 'person' and old.entity_id = remove_id and (
      old.alias_normalized = public.normalize_entity_name((select name from ensembles where id = keep_id)) or exists (
        select 1 from entity_aliases kept where kept.entity_type = 'ensemble' and kept.entity_id = keep_id and kept.alias_normalized = old.alias_normalized
      )
    );
    update entity_aliases set entity_type = 'ensemble', entity_id = keep_id where entity_type = 'person' and entity_id = remove_id;
    if public.normalize_entity_name(remove_name) <> public.normalize_entity_name((select name from ensembles where id = keep_id)) then
      insert into entity_aliases (entity_type, entity_id, alias) values ('ensemble', keep_id, remove_name) on conflict do nothing;
    end if;

    -- Favoriten/Interessen/Duplikat-Kandidaten/Audit-Flags für die Person
    -- kaskadieren automatisch (on delete cascade), es gibt keine
    -- Ensemble-Äquivalente, in die sie sinnvoll umgehängt werden könnten.
    delete from persons where id = remove_id;
  end loop;
end;
$$;
