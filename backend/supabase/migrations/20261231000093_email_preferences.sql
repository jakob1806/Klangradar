-- Erstellt mit Claude Code.
--
-- E-Mail-Einstellungen: bisher gab es nur Push-Schalter
-- (notification_preferences) und eine einzelne Marketing-Einwilligung
-- (profiles.marketing_email_opt_in, bei der Registrierung abgefragt).
--
-- 1. Newsletter = profiles.marketing_email_opt_in (bleibt die einzige Quelle
--    für die Werbe-Einwilligung). Neu: Zeitstempel der Einwilligung als
--    Nachweis (DSGVO Art. 7 Abs. 1), automatisch per Trigger gepflegt.
-- 2. E-Mail-Benachrichtigungen pro Anlass, unabhängig von Push. Default
--    bewusst false: Nutzer wählen E-Mails aktiv, bestehende Accounts
--    bekommen nichts ungefragt.
-- 3. Abmelde-Token pro Nutzer für den Ein-Klick-Abmeldelink in jeder Mail
--    (List-Unsubscribe), damit Abmelden ohne Login funktioniert.

alter table profiles
  add column if not exists marketing_email_opt_in_at timestamptz;

comment on column profiles.marketing_email_opt_in_at is
  'Zeitpunkt der letzten Erteilung der Newsletter-Einwilligung (null = nie bzw. widerrufen).';

create or replace function public.stamp_marketing_email_opt_in()
returns trigger
language plpgsql
as $$
begin
  if new.marketing_email_opt_in is distinct from coalesce(old.marketing_email_opt_in, false) then
    new.marketing_email_opt_in_at := case when new.marketing_email_opt_in then now() else null end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_marketing_email_opt_in on profiles;
create trigger trg_stamp_marketing_email_opt_in
  before insert or update of marketing_email_opt_in on profiles
  for each row execute function public.stamp_marketing_email_opt_in();

-- Bestehende Einwilligungen ohne Zeitstempel: Zeitpunkt unbekannt, daher
-- bewusst NICHT rückwirkend gesetzt (kein erfundener Nachweis).

alter table notification_preferences
  add column if not exists email_weekly_digest boolean not null default false,
  add column if not exists email_followed_new_event boolean not null default false,
  add column if not exists email_event_changes boolean not null default false,
  add column if not exists email_reminder_day_before boolean not null default false,
  add column if not exists email_unsubscribe_token uuid not null default gen_random_uuid();

comment on column notification_preferences.email_weekly_digest is
  'E-Mail "Deine Konzertwoche": passende Termine der kommenden Woche (wöchentlich).';
comment on column notification_preferences.email_followed_new_event is
  'E-Mail bei neuen Terminen gefolgter Personen, Ensembles und Orte.';
comment on column notification_preferences.email_event_changes is
  'E-Mail bei Absage/Verlegung/Änderung gemerkter Konzerte.';
comment on column notification_preferences.email_reminder_day_before is
  'E-Mail-Erinnerung am Vortag gemerkter Konzerte.';
comment on column notification_preferences.email_unsubscribe_token is
  'Geheimer Token für den Ein-Klick-Abmeldelink in E-Mails (Abmelden ohne Login).';

create unique index if not exists notification_preferences_email_unsubscribe_token_idx
  on notification_preferences (email_unsubscribe_token);
