-- Ein einzelner Produktions-Backfill-Aufruf traf einen transienten
-- Providerfehler. Sofort erneut freigeben; künftige Fehler werden durch das
-- Processing-Lease ohnehin automatisch wieder aufgenommen.
update events
set program_retry_after = null
where status = 'scheduled'
  and program_extraction_status = 'error';
