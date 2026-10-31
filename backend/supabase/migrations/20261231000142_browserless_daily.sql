-- Erstellt von Claude Code (31.10.2026): Browserless-Zugang ist erneuert
-- (Secret BROWSERLESS_API_TOKEN). Quellen, die nur gerendert lesbar sind
-- (config.renderJs), höchstens einmal täglich abrufen, damit das
-- Gratis-Kontingent reicht. Der Import hält diese Untergrenze jetzt auch bei
-- der automatischen Takt-Anpassung ein (ingest-source/core.ts).
update public.sources
   set crawl_frequency_minutes = greatest(crawl_frequency_minutes, 1440),
       consecutive_failures = 0
 where status = 'active' and (config->>'renderJs')::boolean is true;
