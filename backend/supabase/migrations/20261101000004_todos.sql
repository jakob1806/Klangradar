-- Nutzerwunsch: freie Redaktions-To-Do-Liste im Admin-Dashboard, z.B. für
-- "diese Veranstaltung hat ein falsches Bild" oder andere Punkte, die nicht
-- in einen der bestehenden strukturierten Review-Flows (content_reports,
-- code_fix_tasks, review-queue) passen. Bewusst ohne Verknüpfung zu einer
-- festen Entität/Tabelle — die genaue Beschreibung trägt den Bezug (welches
-- Event, welches Bild) im Freitext, damit die Liste für beliebige Themen
-- taugt statt nur für Events.
create table todos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null,
  status text not null default 'open' check (status in ('open', 'done')),
  created_by text,
  created_at timestamptz not null default now(),
  done_at timestamptz
);

create index todos_status_idx on todos (status, created_at desc);

alter table todos enable row level security;
create policy "Redaktion liest To-Dos" on todos for select using (is_admin_or_editor());
create policy "Redaktion legt To-Dos an" on todos for insert with check (is_admin_or_editor());
create policy "Redaktion aktualisiert To-Dos" on todos for update using (is_admin_or_editor()) with check (is_admin_or_editor());
create policy "Redaktion löscht To-Dos" on todos for delete using (is_admin_or_editor());

comment on table todos is
  'Freie Redaktions-Aufgabenliste im Admin-Dashboard (Titel + genaue Beschreibung, offen/erledigt) für Punkte, die zu keinem strukturierten Review-Flow gehören, z.B. "Event X hat falsches Bild".';
