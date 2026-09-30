-- Quellengesundheits-Audit (2026-09-30): internal_function_secret() liefert
-- seit der Migration 20261029000002_internal_function_secret_for_cron.sql
-- durchgehend NULL zurück -- der dort als "wichtiger manueller Schritt"
-- dokumentierte einmalige `select vault.create_secret(...)`-Aufruf im SQL
-- Editor wurde nie ausgeführt. Folge: JEDE der 40+ dort umgestellten
-- Cron-Funktionen (u.a. run_all_active_sources -> run-all-sources ->
-- ingest-source, alle hydrate-*-events-Sync-Jobs, Benachrichtigungen,
-- Biografie-/Werk-Anreicherung, Auto-Fix) sendet seither einen leeren
-- 'x-internal-secret'-Header und scheitert an requireInternalAuth() mit
-- 401/403 -- lautlos, weil die Cron-Funktionen selbst laut Design nie
-- werfen (siehe deren "raise warning ... fehlgeschlagen"-Muster). Das
-- gesamte automatische Scraping/Hydration/Enrichment stand seit
-- ca. 2026-08-28 still (sources.last_run_at bei praktisch allen ~70
-- Quellen eingefroren).
--
-- Der Secret-Wert selbst darf laut demselben Kommentar NICHT im Klartext in
-- einer Migration stehen (für jeden mit Repo-Zugriff lesbar). Diese
-- Funktion nimmt den Wert deshalb als Laufzeit-Parameter entgegen, statt
-- ihn hier einzubetten -- der eigentliche Aufruf mit dem echten Wert
-- erfolgt einmalig per RPC direkt nach dem Deploy dieser Migration und
-- landet dadurch an keiner Stelle im Git-Verlauf. Danach ist dieselbe
-- Funktion nur noch für eine künftige Rotation nützlich (erneuter Aufruf
-- mit neuem Wert), daher dauerhaft belassen statt nach einmaliger
-- Nutzung wieder zu entfernen.
create or replace function set_internal_function_secret(secret_value text)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  existing_id uuid;
begin
  if secret_value is null or length(secret_value) < 16 then
    raise exception 'set_internal_function_secret: Wert fehlt oder ist zu kurz (mind. 16 Zeichen)';
  end if;

  select id into existing_id from vault.secrets where name = 'internal_function_secret';

  if existing_id is null then
    perform vault.create_secret(secret_value, 'internal_function_secret');
  else
    perform vault.update_secret(existing_id, secret_value);
  end if;
end;
$$;

-- Nur für die Rolle ausführbar, die admin-artige Wartung macht (postgres/
-- service_role über SQL Editor bzw. per Service-Role-Key per RPC) --
-- bewusst nicht an authenticated/anon vergeben, das Secret darf nicht von
-- App-Nutzer:innen gesetzt werden können.
revoke all on function set_internal_function_secret(text) from public, anon, authenticated;
grant execute on function set_internal_function_secret(text) to service_role;
