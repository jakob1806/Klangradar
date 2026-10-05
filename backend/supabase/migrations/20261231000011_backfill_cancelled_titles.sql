-- Events, deren Titel einen Absage-Marker trägt ("ABGESAGT: …"), standen bisher
-- als normal geplant in der DB (Beispiel: Laeiszhalle, 05.10.2026, Julia
-- Kleiter / Julian Prégardien / Sir András Schiff). Der Scraper erkennt den
-- Marker jetzt (ingest-source/cancellation.ts); hier wird der Bestand
-- nachgezogen. Gleiche Muster wie in der Funktion.
update events
set status = 'cancelled'
where status in ('scheduled', 'sold_out', 'draft')
  and (
    title ~* '^\s*[\[(*]?\s*(abgesagt|entfällt|entfaellt|fällt\s+aus|faellt\s+aus|cancel+ed|annulliert|annulé)\y'
    or title ~* '[\s\-–—:(\[]+(abgesagt|entfällt|cancel+ed)\s*[)\]]?\s*$'
  );

update events
set status = 'postponed'
where status in ('scheduled', 'sold_out', 'draft')
  and title ~* '^\s*[\[(*]?\s*(verschoben|verlegt|postponed|reporté)\y';
