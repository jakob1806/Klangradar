-- Rekonstruiert aus supabase_migrations.schema_migrations.statements der
-- echten Produktions-DB (2026-08-27) -- eine andere Session hatte dies
-- direkt gegen Produktion gepusht, ohne die SQL-Datei je zu committen.
-- Diese Datei stellt nur die Git-Historie wieder her (exakter Wortlaut
-- der bereits angewendeten Statements); die tatsächliche Anwendung auf
-- Produktion ist bereits erfolgt, siehe migration-repair-Verfahren.

-- Eindeutige, offiziell gebräuchliche Suchnamen, die im vorhandenen
-- Aliasbestand noch fehlen. search_all löst sie anschließend generisch auf;
-- in den Clients ist kein BRSO-Sonderfall nötig.
insert into public.entity_aliases (entity_type, entity_id, alias)
select 'ensemble', ensemble.id, alias_name
from public.ensembles ensemble
cross join (values
  ('BRSO'),
  ('BR-Symphonieorchester'),
  ('Bavarian Radio Symphony Orchestra')
) aliases(alias_name)
where ensemble.slug = 'symphonieorchester-des-bayerischen-rundfunks'
  and not ensemble.is_resolution_placeholder
  and not ensemble.is_family_root
on conflict do nothing;
