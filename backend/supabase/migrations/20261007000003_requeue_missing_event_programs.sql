-- Die Referenzanreicherung wurde für viele Veranstaltungen bereits als
-- geprüft markiert, bevor sie den Volltext der offiziellen Veranstaltungs-
-- seite als Kontext verwendete. Dadurch bleiben trotz vorhandener URL keine
-- event_works übrig und die App kann nur einen ehrlichen Leerzustand zeigen.
--
-- Dieser einmalige, idempotente Requeue betrifft ausschließlich veröffent-
-- lichte/geplante Veranstaltungen mit offizieller Quelle und noch keinem
-- strukturierten Werk. Der bestehende enrich-event-references-Cron verarbeitet
-- sie anschließend erneut mit dem aktuellen, konservativen Extraktor. Events,
-- deren Quelle tatsächlich kein konkretes Programm nennt, werden dabei wieder
-- als geprüft markiert; es werden keine Werke aus bloßen Komponistennamen
-- erfunden.

update events e
set references_checked_at = null
where e.status = 'scheduled'
  and (e.website_url is not null or e.ticket_url is not null)
  and not exists (
    select 1
    from event_works ew
    where ew.event_id = e.id
  );

