-- Der erste produktive Gärtnerplatz-Lauf wurde während der seriellen
-- Schreibphase vom Edge-Zeitlimit beendet, nachdem der Response-Hash schon
-- gespeichert war. Nach der parallelen, titelgruppierten Schreiboptimierung
-- den Cache einmalig leeren, damit der vollständige Saisonlauf statt
-- skipped_unchanged ausgeführt wird. Gleiches für den beim Reader-429
-- abgebrochenen Staatsoper-Erstlauf.
update sources
set config = coalesce(config, '{}'::jsonb) - 'httpCache'
where id in (
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'c1100000-0000-4000-8000-000000000002'::uuid
);
