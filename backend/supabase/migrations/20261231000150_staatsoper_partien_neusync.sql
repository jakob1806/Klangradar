-- Erstellt von Claude Code (01.11.2026). Nutzerfeedback: Bei Staatsoper-
-- Vorstellungen steht bei Sänger:innen nur „Solist:in“ statt der Partie.
-- Der Detail-Abgleich (hydrate-staatsoper-events) liest die Partie seit dem
-- 30.10.2026 als role_label, liest aber nur Termine der nächsten 21 Tage
-- erneut. Ältere Abgleiche ohne Partie blieben deshalb stehen.
-- Hier werden alle kommenden Staatsoper-Termine zurückgesetzt, bei denen
-- mindestens ein:e Solist:in ohne role_label verknüpft ist. Der Cron-Job holt
-- sie dann in den nächsten Läufen erneut.
update public.events e
set staatsoper_detail_synced_at = null,
    staatsoper_detail_sync_error = null
where e.website_url ilike '%staatsoper.de/%'
  and e.start_datetime >= now()
  and exists (
    select 1 from public.event_participants p
    where p.event_id = e.id
      and p.person_id is not null
      and coalesce(p.role, 'solist') = 'solist'
      and nullif(trim(p.role_label), '') is null
  );
