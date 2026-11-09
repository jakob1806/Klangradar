-- Datenschutz (09.11.2026): vollständiges Löschen und Speicherfristen.
-- 1) Eigene Chatfotos löschen dürfen (Konto löschen, Nachricht löschen).
drop policy if exists "Chatfotos löschen" on storage.objects;
create policy "Chatfotos löschen" on storage.objects for delete
  using (bucket_id = 'chat-images' and owner = auth.uid());

-- 2) Pfade der eigenen Dateien, damit die App sie vor dem Konto-Löschen
--    über die Storage-API entfernt (direktes Löschen in storage.objects per
--    SQL lässt die Datei liegen).
create or replace function public.my_storage_paths()
returns table (bucket text, path text)
language sql stable security definer set search_path = public as $$
  select 'chat-images', m.image_path from chat_messages m
  where m.sender_id = auth.uid() and m.image_path is not null
  union all
  select 'diary-photos', p from concert_diary_entries d, unnest(coalesce(d.photo_paths, '{}')) p
  where d.user_id = auth.uid()
  union all
  select 'diary-photos', p from user_concert_entries u, unnest(coalesce(u.photo_paths, '{}')) p
  where u.user_id = auth.uid();
$$;
grant execute on function public.my_storage_paths() to authenticated;

-- 3) Beim Löschen des Kontos eigene Chatnachrichten mitlöschen (statt sie
--    anonym stehen zu lassen) und „schreibt …“ zurücksetzen.
create or replace function public.chat_delete_user_content()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.chat_messages where sender_id = old.id;
  return old;
end; $$;
drop trigger if exists chat_delete_user_content on auth.users;
create trigger chat_delete_user_content before delete on auth.users
  for each row execute function public.chat_delete_user_content();

-- 4) Speicherfristen: Wallet-Kartendaten (enthalten den Ticket-Code) 30 Tage
--    nach dem Konzert, Push-Protokoll nach 180 Tagen, Absturzberichte nach 90.
create or replace function public.privacy_retention_cleanup()
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from wallet_passes w using events e
  where e.id = w.event_id and e.start_datetime < now() - interval '30 days';
  delete from wallet_passes where event_id is null and updated_at < now() - interval '30 days';
  delete from push_log where sent_at < now() - interval '180 days';
  delete from app_diagnostics where created_at < now() - interval '90 days';
end; $$;
select cron.unschedule('privacy-retention-cleanup') where exists (select 1 from cron.job where jobname = 'privacy-retention-cleanup');
select cron.schedule('privacy-retention-cleanup', '17 3 * * *', $$ select public.privacy_retention_cleanup(); $$);

-- 5) „Problem melden“ in der App (zweiter Kontaktweg neben E-Mail, Impressum).
create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  contact text check (contact is null or char_length(contact) <= 200),
  message text not null check (char_length(message) between 3 and 4000),
  app_version text,
  created_at timestamptz not null default now(),
  handled_at timestamptz
);
alter table public.support_messages enable row level security;
drop policy if exists "Eigene Supportnachricht anlegen" on public.support_messages;
create policy "Eigene Supportnachricht anlegen" on public.support_messages for insert to authenticated
  with check (user_id = auth.uid());
grant insert on public.support_messages to authenticated;
