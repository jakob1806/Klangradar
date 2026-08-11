-- Nutzerwunsch: "bei erneut versuchen soll einfach eine KI diese fehler
-- durchgehen und beheben ... KI darf auch die fehler selbst beheben." Die
-- Edge Function auto-fix-content-report läuft aber zur Laufzeit isoliert
-- und hat KEINEN Zugriff auf das Git-Repo — sie kann selbst keinen Code
-- ändern/deployen. Erkennt die KI beim erneuten Versuch, dass die
-- eigentliche Ursache ein Code-Bug ist (z.B. ein kaputter Scraper), legt sie
-- stattdessen hier eine fertige, in sich geschlossene Aufgabe an, die
-- Claude Code (mit echtem Repo-Zugriff) beim nächsten Mal aufgreifen kann —
-- Nutzerwunsch entsprechend "wie eine Chatnachricht mit der
-- Fehlerkorrektur", nur eben vorbereitet statt manuell getippt.
create table code_fix_tasks (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references content_reports(id) on delete cascade,
  fix_id uuid references content_report_fixes(id) on delete set null,
  title text not null,
  -- Selbstständiger, direkt an Claude Code übergebbarer Auftragstext (Datei-
  -- /Funktionsverdacht, Symptom, Beleg) — bewusst kein Verweis auf Kontext,
  -- der nur innerhalb dieser Konversation bekannt ist.
  prompt text not null,
  status text not null default 'pending' check (status in ('pending', 'claimed', 'done')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index code_fix_tasks_status_idx on code_fix_tasks (status, created_at desc);

alter table code_fix_tasks enable row level security;
create policy "Redaktion liest Code-Aufgaben" on code_fix_tasks for select using (is_admin_or_editor());
create policy "Redaktion schreibt Code-Aufgaben" on code_fix_tasks for insert with check (is_admin_or_editor());
create policy "Redaktion aktualisiert Code-Aufgaben" on code_fix_tasks for update using (is_admin_or_editor()) with check (is_admin_or_editor());

comment on table code_fix_tasks is
  'Warteschlange für Fälle, in denen der freiere Nutzermeldungs-Fix (retry-Modus, auto-fix-content-report) einen Code-Bug statt eines Datenproblems vermutet — für Claude Code zur manuellen/nächsten Bearbeitung, da Edge Functions keinen Repo-/Deploy-Zugriff haben.';

-- 'code_bug_suspected' als vierter möglicher Ausgang neben fixed/
-- needs_manual_review/error (siehe content_report_fixes-Migration).
alter table content_report_fixes drop constraint content_report_fixes_status_check;
alter table content_report_fixes add constraint content_report_fixes_status_check
  check (status in ('fixed', 'needs_manual_review', 'error', 'code_bug_suspected'));
