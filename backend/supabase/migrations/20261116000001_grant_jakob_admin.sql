-- Globaler Klangradar-Admin: wird nur eingefügt, wenn der Nutzer nach dem
-- ersten Login bereits in auth.users existiert. ON CONFLICT hält die
-- Migration idempotent und ergänzt keine zweite Rolle.
insert into user_roles (user_id, role)
select id, 'admin'::app_role
from auth.users
where lower(email) = 'jakob.liess@outlook.de'
on conflict (user_id, role) do nothing;
