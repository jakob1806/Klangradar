-- Marketing-E-Mails brauchen eine separate, freiwillige Einwilligung.
-- Der Default bleibt bewusst false; bestehende Accounts werden niemals
-- nachträglich als eingewilligt behandelt.
alter table profiles
  add column if not exists marketing_email_opt_in boolean not null default false;

comment on column profiles.marketing_email_opt_in is
  'Separate freiwillige Einwilligung für Marketing-E-Mails; unabhängig von AGB und Datenschutz.';
