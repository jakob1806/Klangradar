-- Schließt die Lücke, die die neue requireInternalAuth()-Prüfung in den
-- Edge Functions (siehe backend/supabase/functions/_shared/internalAuth.ts)
-- sonst gegen die eigenen Cron-Jobs aufreißen würde: bisher riefen alle
-- unten stehenden Functions ihre jeweilige Edge Function nur mit dem
-- ÖFFENTLICHEN Anon-Key auf (apikey/Authorization-Header) — der reicht ab
-- sofort nicht mehr, weil dieselbe Prüfung verhindern soll, dass JEDE
-- Person mit dem (im App-Bundle öffentlichen) Anon-Key dieselben
-- service-role-mächtigen Functions beliebig oft aufrufen kann (Kosten-
-- Abuse bei LLM-/Bildsuche-Aufrufen, Scraping-Abuse, Notification-Spam,
-- ungewollte Schreibzugriffe — siehe Sicherheitsanalyse).
--
-- Secret-Speicherung über Supabase Vault statt Klartext in der Migration
-- (anders als der bisherige Anon-Key, der bewusst öffentlich ist, MUSS
-- dieses Secret geheim bleiben — ein Klartext-Wert hier wäre für jeden mit
-- Repo-Zugriff lesbar). internal_function_secret() liest ihn zur Laufzeit
-- aus vault.decrypted_secrets.
--
-- WICHTIGER MANUELLER SCHRITT VOR DEM DEPLOY DIESER MIGRATION (kann nicht
-- aus der Migration selbst heraus passieren, da der Wert an drei Stellen
-- synchron sein muss):
--   1. Ein zufälliges Secret erzeugen (z.B. `openssl rand -hex 32`).
--   2. In Supabase Vault hinterlegen (SQL Editor, einmalig):
--        select vault.create_secret('<erzeugter-wert>', 'internal_function_secret');
--   3. Denselben Wert als Edge-Function-Secret setzen:
--        supabase secrets set INTERNAL_FUNCTION_SECRET=<erzeugter-wert>
--   4. Denselben Wert als Server-Env-Var im Admin-Dashboard-Hosting setzen:
--        INTERNAL_FUNCTION_SECRET=<erzeugter-wert> (Next.js Server Action,
--        NICHT NEXT_PUBLIC_-prefixed — darf nicht ins Client-Bundle)
-- Ohne Schritt 1-2 gibt internal_function_secret() NULL zurück, wodurch
-- der 'x-internal-secret'-Header in den unten stehenden Functions leer
-- bleibt und die Edge Functions weiterhin 401/403 liefern, bis das Secret
-- gesetzt ist — die Cron-Jobs selbst werfen dabei nicht (siehe jeweiliges
-- "raise warning ... net.http_post fehlgeschlagen"-Muster), sie laufen nur
-- so lange leer wie bisher schon bei jedem anderen Function-Fehler auch.
create or replace function internal_function_secret()
returns text
language sql
security definer
set search_path = public, vault
stable
as $$
  select decrypted_secret from vault.decrypted_secrets
  where name = 'internal_function_secret'
  limit 1;
$$;

-- (übernommen aus 20261015000004_automatic_ensemble_venue_biographies.sql, nur der headers-Block ergänzt)
create or replace function public.enqueue_new_entity_biography()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_type text := case tg_table_name when 'ensembles' then 'ensemble' else 'venue' end;
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if nullif(btrim(new.description_de), '') is null then
    perform net.http_post(
      url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-biographies',
      body := jsonb_build_object('type', v_type, 'entityId', new.id),
      headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_key,'Authorization','Bearer ' || v_key)
    );
  end if;
  if nullif(btrim(new.photo_url), '') is null then
    perform net.http_post(
      url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-images',
      body := jsonb_build_object('type', v_type, 'limit', 1, 'entityIds', jsonb_build_array(new.id), 'fastFallback', true),
      headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_key,'Authorization','Bearer ' || v_key)
    );
  end if;
  return new;
exception when others then
  raise warning 'Neue Entität % konnte nicht sofort angereichert werden: %', new.id, sqlerrm;
  return new;
end; $$;

-- (übernommen aus 20261015000003_automatic_new_person_enrichment.sql, nur der headers-Block ergänzt)
create or replace function public.enqueue_new_person_enrichment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  if nullif(btrim(new.biography_de), '') is null then
    perform net.http_post(
      url := v_supabase_url || '/functions/v1/enrich-entity-oncall',
      body := jsonb_build_object('entityType', 'person', 'entityId', new.id),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
        'apikey', v_anon_key,
        'Authorization', 'Bearer ' || v_anon_key
      )
    );
  end if;

  if nullif(btrim(new.photo_url), '') is null then
    perform net.http_post(
      url := v_supabase_url || '/functions/v1/enrich-entity-images',
      body := jsonb_build_object(
        'type', 'person',
        'limit', 1,
        'entityIds', jsonb_build_array(new.id),
        'fastFallback', true
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
        'apikey', v_anon_key,
        'Authorization', 'Bearer ' || v_anon_key
      )
    );
  end if;

  return new;
exception when others then
  -- Ein externer KI-/Netzwerkfehler darf den eigentlichen Personen-Import
  -- niemals zurückrollen. Die regulären Hintergrund-Crons übernehmen dann.
  raise warning 'Neue Person % konnte nicht sofort angereichert werden: % (%)', new.id, sqlerrm, sqlstate;
  return new;
end;
$$;

-- (übernommen aus 20261015000004_automatic_ensemble_venue_biographies.sql, nur der headers-Block ergänzt)
create or replace function public.run_ensemble_ai_biography_enrichment()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-biographies',
    body := '{"type":"ensemble","limit":8}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_key,'Authorization','Bearer ' || v_key)
  );
exception when others then raise warning 'Ensemble-Biografielauf fehlgeschlagen: %', sqlerrm;
end; $$;

-- (übernommen aus 20261015000001_fast_person_biographies_and_image_queue.sql, nur der headers-Block ergänzt)
create or replace function public.run_person_ai_biography_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-person-biographies',
    body := '{"limit":16}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon_key,'Authorization','Bearer ' || v_anon_key)
  );
exception when others then
  raise warning 'run_person_ai_biography_enrichment fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261015000002_person_image_web_fallback.sql, nur der headers-Block ergänzt)
create or replace function public.run_person_image_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-entity-images',
    body := '{"type":"person","limit":4,"fastFallback":true}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon_key,'Authorization','Bearer ' || v_anon_key)
  );
exception when others then
  raise warning 'run_person_image_enrichment fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261015000004_automatic_ensemble_venue_biographies.sql, nur der headers-Block ergänzt)
create or replace function public.run_venue_ai_biography_enrichment()
returns void language plpgsql as $$
declare
  v_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := 'https://zqgzcspeqllrihfwmayn.supabase.co/functions/v1/enrich-entity-biographies',
    body := '{"type":"venue","limit":8}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_key,'Authorization','Bearer ' || v_key)
  );
exception when others then raise warning 'Venue-Biografielauf fehlgeschlagen: %', sqlerrm;
end; $$;

-- (übernommen aus 20260818000005_run_all_sources_orchestrator.sql, nur der headers-Block ergänzt)
create or replace function run_all_active_sources()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/run-all-sources',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
end;
$$;

-- (übernommen aus 20261006000009_auto_fix_content_report_cron.sql, nur der headers-Block ergänzt)
create or replace function run_auto_fix_content_reports()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/auto-fix-content-report',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_auto_fix_content_reports: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261016000008_biennale_detail_sync.sql, nur der headers-Block ergänzt)
create or replace function run_biennale_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-biennale-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_biennale_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261016000007_br_chor_detail_sync.sql, nur der headers-Block ergänzt)
create or replace function run_br_chor_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-br-chor-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_br_chor_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261015000012_brso_detail_sync.sql, nur der headers-Block ergänzt)
create or replace function run_brso_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-brso-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_brso_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261016000019_check_ticket_links_cron.sql, nur der headers-Block ergänzt)
create or replace function run_check_ticket_links()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/check-ticket-links',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_check_ticket_links: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260908000005_person_ensemble_enrichment_cron.sql, nur der headers-Block ergänzt)
create or replace function run_ensemble_profile_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-ensemble-profile',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_ensemble_profile_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260908000008_entity_candidate_resolution_cron.sql, nur der headers-Block ergänzt)
create or replace function run_entity_candidate_resolution()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/resolve-entity-candidates',
    body := '{"limit": 8}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_entity_candidate_resolution: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260910000008_event_price_enrichment_cron.sql, nur der headers-Block ergänzt)
create or replace function run_event_price_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-event-prices',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_event_price_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260907000003_event_reference_enrichment_cron.sql, nur der headers-Block ergänzt)
create or replace function run_event_reference_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-event-references',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_event_reference_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261016000006_gaertnerplatz_detail_sync.sql, nur der headers-Block ergänzt)
create or replace function run_gaertnerplatz_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-gaertnerplatz-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_gaertnerplatz_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261015000014_gasteig_detail_sync.sql, nur der headers-Block ergänzt)
create or replace function run_gasteig_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-gasteig-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_gasteig_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260909000002_increase_image_enrichment_batch.sql, nur der headers-Block ergänzt)
create or replace function run_image_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-entity-images',
    body := '{"limit": 20}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_image_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261015000016_mko_detail_sync.sql, nur der headers-Block ergänzt)
create or replace function run_mko_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-mko-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_mko_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261015000013_mphil_detail_sync.sql, nur der headers-Block ergänzt)
create or replace function run_mphil_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-mphil-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_mphil_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261002000015_notify_changes_cron.sql, nur der headers-Block ergänzt)
create or replace function run_notify_changes()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/notify-changes',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_notify_changes: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261007000013_notify_followed_entity_events_cron.sql, nur der headers-Block ergänzt)
create or replace function run_notify_followed_entity_events()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/notify-followed-entity-events',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_notify_followed_entity_events: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261016000014_notify_reengagement_cron.sql, nur der headers-Block ergänzt)
create or replace function run_notify_reengagement()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/notify-reengagement',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_notify_reengagement: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261002000010_notify_reminders_cron.sql, nur der headers-Block ergänzt)
create or replace function run_notify_reminders()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/notify-reminders',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_notify_reminders: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260908000007_person_duplicate_resolution_cron.sql, nur der headers-Block ergänzt)
create or replace function run_person_duplicate_resolution()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/resolve-person-duplicates',
    body := '{"limit": 15}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_person_duplicate_resolution: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260908000005_person_ensemble_enrichment_cron.sql, nur der headers-Block ergänzt)
create or replace function run_person_profile_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-person-profile',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_person_profile_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261013000007_staatsoper_detail_sync_cron.sql, nur der headers-Block ergänzt)
create or replace function run_staatsoper_detail_sync()
returns void
language plpgsql
as $$
declare
  v_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_url || '/functions/v1/hydrate-staatsoper-events',
    body := '{"limit":5}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json',
      'x-internal-secret', internal_function_secret(),'apikey',v_anon,'Authorization','Bearer ' || v_anon)
  );
exception when others then
  raise warning 'run_staatsoper_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260908000002_venue_profile_enrichment_cron.sql, nur der headers-Block ergänzt)
create or replace function run_venue_profile_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-venue-details',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_venue_profile_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20261002000005_work_composer_enrichment_cron.sql, nur der headers-Block ergänzt)
create or replace function run_work_composer_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-work-composer',
    body := '{"limit": 10}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_work_composer_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;

-- (übernommen aus 20260908000010_work_profile_enrichment_cron.sql, nur der headers-Block ergänzt)
create or replace function run_work_profile_enrichment()
returns void
language plpgsql
as $$
declare
  v_supabase_url text := 'https://zqgzcspeqllrihfwmayn.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpxZ3pjc3BlcWxscmloZndtYXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxMjgwNjQsImV4cCI6MjA5OTcwNDA2NH0.3ClVL1kfQ3_ATqW0wSeggv3p-OlLlEnAt50_8R_voNg';
begin
  perform net.http_post(
    url := v_supabase_url || '/functions/v1/enrich-work-profile',
    body := '{"limit": 5}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-internal-secret', internal_function_secret(),
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    )
  );
exception when others then
  raise warning 'run_work_profile_enrichment: net.http_post fehlgeschlagen: % (%)', sqlerrm, sqlstate;
end;
$$;