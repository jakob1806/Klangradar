-- Beide redaktionell verwendeten Jakob-Konten erhalten denselben globalen
-- Klangradar-Adminzugang. Damit erscheinen in der nativen App sowohl
-- Redaktionsmodus als auch der daran gekoppelte Marketing-Screenshotbereich.
-- Die Abfrage ist absichtlich idempotent und funktioniert auch, wenn eines
-- der Konten erst nach dem Migrations-Deploy angelegt wurde: ein späterer
-- erneuter Migrationslauf bzw. das Runbook kann dieselbe Anweisung gefahrlos
-- erneut ausführen.
insert into user_roles (user_id, role)
select id, 'admin'::app_role
from auth.users
where lower(email) in (
  'jakob.liess@outlook.de',
  'jakob@klangradar.com'
)
on conflict (user_id, role) do nothing;
