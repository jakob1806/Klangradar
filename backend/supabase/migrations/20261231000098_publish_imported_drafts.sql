-- Erstellt von Claude Code (Nutzerwunsch 23.10.2026): automatisch über die
-- Importquellen gefundene Konzerte veröffentlichen statt als Entwurf liegen
-- zu lassen. ingest-source veröffentlicht neue Konzerte ab jetzt direkt;
-- diese Migration holt die vorhandenen Import-Entwürfe nach.
--
-- Absagen/Verschiebungen werden vorher erkannt (gleiche Regeln wie
-- ingest-source/cancellation.ts: Marker im Titel oder eindeutige Aussage in
-- der Beschreibung). Nicht angefasst: Entwürfe ohne Quelle (von
-- Veranstalter:innen/Redaktion angelegt), vergangene Termine und von der
-- Redaktion abgelehnte Imports (review_status = 'rejected').

do $$
declare
  v_cancelled int;
  v_postponed int;
  v_published int;
begin
  create temporary table import_drafts on commit drop as
    select id, title, coalesce(description_de, '') as description
    from events
    where status = 'draft'
      and source_id is not null
      and start_datetime >= now()
      and review_status <> 'rejected';

  update events e set status = 'cancelled', updated_at = now()
  from import_drafts d
  where e.id = d.id and (
    d.title ~* '^\s*[\[(*]?\s*(abgesagt|entfällt|entfaellt|fällt\s+aus|faellt\s+aus|cancel+ed|annulliert)\M'
    or d.title ~* '[\s\-–—:(\[]+(abgesagt|entfällt|cancel+ed)\s*[)\]]?\s*$'
    or d.description ~* '(konzert|veranstaltung|vorstellung|aufführung|abend|termin)\s+(ist|wurde|muss|musste|wird)\s+(leider\s+)?(krankheitsbedingt\s+)?(abgesagt|ersatzlos\s+gestrichen)'
    or d.description ~* '(konzert|veranstaltung|vorstellung|aufführung|termin)\s+(entfällt|fällt\s+(leider\s+)?aus|findet\s+(leider\s+)?nicht\s+statt)'
    or d.description ~* 'this\s+(concert|event|performance)\s+(has\s+been|is)\s+cancel+ed'
  );
  get diagnostics v_cancelled = row_count;

  update events e set status = 'postponed', updated_at = now()
  from import_drafts d
  where e.id = d.id and e.status = 'draft' and (
    d.title ~* '^\s*[\[(*]?\s*(verschoben|verlegt|postponed)\M'
    or d.description ~* '(konzert|veranstaltung|vorstellung|aufführung|termin)\s+(ist|wurde|muss|wird)\s+(leider\s+)?(auf\s+.{1,40}?\s+)?(verschoben|verlegt)'
  );
  get diagnostics v_postponed = row_count;

  update events e set status = 'scheduled', updated_at = now()
  from import_drafts d
  where e.id = d.id and e.status = 'draft';
  get diagnostics v_published = row_count;

  raise notice 'Import-Entwürfe: % veröffentlicht, % als abgesagt, % als verschoben markiert', v_published, v_cancelled, v_postponed;

  -- Dokumentation in den Quellen (ingest-source veröffentlicht ohnehin immer).
  update sources set config = coalesce(config, '{}'::jsonb) || '{"autoPublish": true}'::jsonb
  where coalesce((config->>'autoPublish')::boolean, false) = false;
end $$;
