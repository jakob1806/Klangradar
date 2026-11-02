-- Erstellt von Claude Code (02.11.2026). Nutzermeldung: Bei allen
-- Aufführungen der Bayerischen Staatsoper waren die Besetzungen weg.
-- Ursache: Der Reader liefert die Besetzung im Markdown seit Kurzem nur noch
-- als Rollen ohne Namen. Der Abgleich hat das als vollständige Besetzung
-- übernommen und alle Personen ersetzt – übrig blieb meist nur das Orchester.
-- hydrate-staatsoper-events liest die Namen jetzt aus dem HTML und ersetzt
-- ohne Personen nie mehr. Hier werden alle kommenden Staatsoper-Termine ohne
-- verknüpfte Person zurückgesetzt, damit der Cron-Job sie neu abgleicht.
update public.events e
set staatsoper_detail_synced_at = null,
    staatsoper_detail_sync_error = null
where e.website_url ilike '%staatsoper.de/%'
  and e.start_datetime >= now() - interval '1 day'
  and not exists (
    select 1 from public.event_participants p
    where p.event_id = e.id and p.person_id is not null
  );
