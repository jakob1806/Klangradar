-- Der 8-Lane-Nachlauf erreichte wegen der großen Saisonmenge nur Februar.
-- Nach Erweiterung auf 20 titelisolierte Lanes den Response-Hash erneut
-- leeren, damit der komplette Spielplan unmittelbar nachgezogen wird.
update sources
set config = coalesce(config, '{}'::jsonb) - 'httpCache'
where id = 'c1100000-0000-4000-8000-000000000002'::uuid;
