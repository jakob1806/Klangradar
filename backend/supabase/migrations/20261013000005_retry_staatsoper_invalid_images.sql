-- Offensichtliche Sponsor-/Logo-Fehlimporte entfernen und alle kommenden
-- Staatsoper-Termine ohne ein valides Eventbild erneut einreihen. Manuell
-- gepflegte oder bereits plausible Produktionsbilder bleiben erhalten.
update events
set image_urls = coalesce((
  select array_agg(url order by ord)
  from unnest(image_urls) with ordinality as item(url, ord)
  where url !~* '(bmw|logo|partner|unicredit|zeitstrahl|placeholder|dummy)'
), '{}'::text[])
where website_url ilike '%staatsoper.de/%'
  and start_datetime >= now();

update events
set staatsoper_detail_synced_at = null,
    staatsoper_detail_sync_error = null
where website_url ilike '%staatsoper.de/%'
  and start_datetime >= now()
  and cardinality(image_urls) = 0;
