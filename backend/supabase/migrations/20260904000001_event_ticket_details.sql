-- Auf Nutzerwunsch: jede Veranstaltung soll einen gut sichtbaren, pro
-- Event individuell gepflegten Ticket-Bereich bekommen (Status, Preis,
-- Link, optionale Hinweise) — bisher unbespielte Felder ergänzen, kein
-- Rückgriff auf Venue-Daten (die gab es hier nie, ticket_url/price_*/
-- is_free/remaining_tickets_status lebten schon immer auf events selbst).
--
-- remaining_tickets_status war bisher ein ungeprüftes text-Feld ohne
-- festgelegten Werteraum (in der Praxis nur informell "few_left" benutzt,
-- siehe home_providers.dart) — aktuell bei ALLEN Events null. Ein
-- Check-Constraint jetzt (statt erst nachträglich, wenn schon
-- widersprüchliche Werte existieren) verhindert künftige Tippfehler/
-- Wildwuchs, ohne bestehende Daten zu gefährden.
alter table events add constraint events_remaining_tickets_status_check
  check (remaining_tickets_status is null or remaining_tickets_status in (
    'available', 'few_left', 'sold_out', 'box_office_only'
  ));

-- Optionale Zusatzhinweise (Einlasszeit, Altersbeschränkung, Ermäßigung,
-- Vorverkaufsgebühr) — bewusst freier Text statt eigener strukturierter
-- Typen: die Formulierungen variieren stark zwischen Quellen/Veranstaltern
-- ("Einlass 19 Uhr" vs. "Einlass eine Stunde vor Beginn"), ein starres
-- Schema hätte hier mehr Fälle ausgeschlossen als abgedeckt.
alter table events add column doors_info text;
alter table events add column age_restriction text;
alter table events add column discount_info text;
alter table events add column presale_fee_info text;
