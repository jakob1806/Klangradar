-- Erstellt von Claude Code (24.10.2026): MPhil-Abgleich mit neuem Parser
-- (drei Titelvarianten, deutsche Werktitel) für alle kommenden Termine neu
-- durchlaufen lassen – der letzte Reset lief noch mit dem alten Code, weil
-- der Edge-Function-Deploy damals an Docker scheiterte. Dazu 15 statt 5
-- Termine pro Lauf und erneuter Versuch für Werkeinführungen.
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
    body := '{"limit":15}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','apikey',v_anon,'Authorization','Bearer ' || v_anon,
      'x-internal-secret', internal_function_secret()),
    timeout_milliseconds := 150000
  );
exception when others then
  raise warning 'run_mphil_detail_sync: % (%)', sqlerrm, sqlstate;
end;
$$;

update events
set mphil_detail_synced_at = null, mphil_detail_sync_error = null
where start_datetime >= now()
  and (website_url ilike '%mphil.de/%' or external_id ilike '%mphil.de/%');

update works set introduction_checked_at = null
where introduction_de is null and introduction_checked_at is not null;

-- Bildqualität: Vorschaubilder von in-muenchen.de (w=265,h=186) auf volle
-- Größe umschreiben (gleiche Regel wie _shared/imageUrlUpgrade.ts).
update events
set image_urls = array(
  select regexp_replace(u, '/(w|h|width|height|fit)=[^/?#]*$', '/w=1600,fit=scale-down')
  from unnest(image_urls) u)
where start_datetime >= now() - interval '1 day'
  and exists (select 1 from unnest(image_urls) u where u like '%/cdn-cgi/imagedelivery/%');
