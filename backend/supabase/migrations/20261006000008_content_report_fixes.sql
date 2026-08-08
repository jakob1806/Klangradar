-- Nutzerwunsch: "baue ein, dass von nutzer gemeldete fehler automatisch
-- (und auf button befehl) gefixxt und behoben werden. dazu soll auch immer
-- ein bericht erstellt werden." — content_reports selbst ändert laut
-- eigenem Seitenkommentar bewusst NIE automatisch Daten; diese Tabelle ist
-- das separate Protokoll für den NEUEN automatisierten Fix-Versuch (Edge
-- Function auto-fix-content-report), unabhängig vom bisherigen rein
-- redaktionellen "Erledigt"/"Verwerfen"-Fluss.
--
-- Ein Report kann mehrfach versucht werden (manueller "Erneut versuchen"-
-- Klick nach einem needs_manual_review/error-Ergebnis) — deshalb 1:n statt
-- eine Spalte direkt auf content_reports, und explizit KEIN Unique-
-- Constraint auf report_id.
create table content_report_fixes (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references content_reports(id) on delete cascade,
  status text not null check (status in ('fixed', 'needs_manual_review', 'error')),
  -- Freitext-Begründung der KI bzw. der Regel-Logik (z.B. bei wrong_image),
  -- immer gefüllt — auch im Fehlerfall/needs_manual_review, damit die
  -- Redaktion nachvollziehen kann, WARUM nichts automatisch geändert wurde.
  diagnosis text not null,
  -- Kurze menschenlesbare Zusammenfassung der tatsächlich vorgenommenen
  -- Änderung, nur bei status='fixed' gefüllt.
  action_taken text,
  -- [{table, id, field, before, after}, ...] — leer, wenn nichts geändert wurde.
  fields_changed jsonb not null default '[]'::jsonb,
  -- Welcher AI-Provider geantwortet hat (siehe _shared/ai/router.ts), oder
  -- null bei rein regelbasierten Fällen (z.B. wrong_image) bzw. wenn kein
  -- Provider konfiguriert war.
  ai_provider text,
  created_at timestamptz not null default now()
);

create index content_report_fixes_report_id_idx on content_report_fixes (report_id, created_at desc);

alter table content_report_fixes enable row level security;
create policy "Redaktion liest Fix-Berichte" on content_report_fixes for select using (is_admin_or_editor());
create policy "Redaktion schreibt Fix-Berichte" on content_report_fixes for insert with check (is_admin_or_editor());

comment on table content_report_fixes is
  'Protokoll jedes automatischen Fix-Versuchs (Button oder Cron) für eine content_reports-Zeile — siehe auto-fix-content-report Edge Function. Ein Report kann mehrere Zeilen haben (mehrere Versuche).';
