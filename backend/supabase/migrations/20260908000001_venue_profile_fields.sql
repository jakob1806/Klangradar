-- Nutzeranfrage (Venue-Profile): "vollständige Adresse, Geo-Koordinaten,
-- Stadtteil, Website, Telefon und E-Mail", "Geschichte und künstlerisches
-- Profil", "Anreise: ÖPNV-Haltestellen, Parken, Fahrrad, Taxi und
-- Fußweg", "Einlass-, Garderoben-, Sicherheits- und gastronomische
-- Hinweise", "korrekte Entitätsart". Geo-Koordinaten (location, PostGIS
-- geography) und ÖPNV/Parken (mvv_stops/parking_info_de) existieren
-- bereits — hier nur die tatsächlich fehlenden Felder.
alter table venues add column phone text;
alter table venues add column email text;
alter table venues add column history_de text;
alter table venues add column district text;
alter table venues add column venue_type text;
-- Fahrrad/Taxi/Fußweg ergänzend zu den bereits vorhandenen mvv_stops/
-- parking_info_de (ÖPNV bzw. Auto), statt für jeden einzelnen
-- Verkehrsträger eine eigene Spalte anzulegen — die Formulierungen
-- variieren stark zwischen Quellen, ein starres Schema würde hier mehr
-- Fälle ausschließen als abdecken (gleiche Begründung wie bei den
-- optionalen Event-Ticket-Feldern, 20260904000001_event_ticket_details.sql).
alter table venues add column arrival_info_de text;
alter table venues add column doors_info_de text;
alter table venues add column catering_info_de text;
