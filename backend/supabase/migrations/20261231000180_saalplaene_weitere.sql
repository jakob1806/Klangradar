-- Erstellt von Claude Code (18.11.2026): Saalpläne für weitere Häuser – nur
-- offizielle, geprüfte Seiten (HTTP 200, Titel „Saalplan/Sitzplan“).
update venues set seating_plan_url = 'https://www.konzerthaus.de/de/saalplan-preise'
  where seating_plan_url is null and name ilike 'Konzerthaus Berlin%';
update venues set seating_plan_url = 'https://www.volksoper.at/volksoper_wien/karten_abos/Sitzplan_Preise.de.php'
  where seating_plan_url is null and name ilike 'Volksoper Wien%';
update venues set seating_plan_url = 'https://www.berliner-philharmoniker.de/konzerte/ticketinfo/preise-saalplaene/'
  where seating_plan_url is null and (name ilike 'Philharmonie Berlin%' or name ilike 'Kammermusiksaal der Philharmonie%');
update venues set seating_plan_url = 'https://www.konzerthaus.at/saalplaene'
  where seating_plan_url is null and name ilike 'Wiener Konzerthaus%';
