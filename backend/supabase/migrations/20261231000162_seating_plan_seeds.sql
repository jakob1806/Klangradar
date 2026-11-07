-- Erste Saalpläne aus offiziellen Quellen (Recherche 07.11.2026). Nur wo noch
-- keiner hinterlegt ist; Redaktion kann unter /saalplaene ersetzen.
--  * Isarphilharmonie: Saalplan-Seite der Münchner Philharmoniker
--  * Nationaltheater: Saalplan-Seite der Bayerischen Staatsoper
--  * Prinzregententheater, Cuvilliés-Theater: Saalplan-PDF der Staatsoper
--    (Spielzeit 21/22 – Platzaufteilung, Preise ggf. veraltet)
update public.venues set seating_plan_url = 'https://www.mphil.de/en/concerts-tickets/seating-plan'
where seating_plan_url is null and name ilike '%isarphilharmonie%';

update public.venues set seating_plan_url = 'https://www.staatsoper.de/en/seating-plans'
where seating_plan_url is null and name ilike 'nationaltheater%';

update public.venues set seating_plan_url = 'https://www.staatsoper.de/media/content/PDF/BSO_Saalplaene_21_22.pdf'
where seating_plan_url is null and (name ilike 'prinzregententheater%' or name ilike 'cuvilli%');
