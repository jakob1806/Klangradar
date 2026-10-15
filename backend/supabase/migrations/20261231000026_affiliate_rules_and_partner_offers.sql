-- Erstellt von Claude Code (Punkte 17 und 18 der Ausbauliste).
--
-- affiliate_rules: Ticketlinks auf Partner-Domains werden in der App beim
-- Öffnen umgeschrieben (Parameter anhängen oder über einen Tracking-Link
-- leiten). Leer = keine Änderung. Einträge legt die Redaktion an, sobald ein
-- Partnerprogramm (z. B. Eventim über Awin) bestätigt ist.
create table if not exists public.affiliate_rules (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  host_suffix text not null,            -- z. B. "eventim.de"
  url_template text,                    -- z. B. "https://www.awin1.com/cread.php?awinmid=1&awinaffid=2&ued={url}"
  append_params jsonb not null default '{}'::jsonb, -- z. B. {"affiliate":"KLR"}
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint affiliate_rules_has_target check (url_template is not null or append_params <> '{}'::jsonb),
  constraint affiliate_rules_template_has_url check (url_template is null or url_template like '%{url}%')
);
alter table public.affiliate_rules enable row level security;
create policy "Alle lesen aktive Affiliate-Regeln" on public.affiliate_rules for select using (active or is_admin_or_editor());
create policy "Redaktion pflegt Affiliate-Regeln" on public.affiliate_rules for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- partner_offers: Vorteile für Klangradar-Plus-Mitglieder (z. B. 10 % im
-- Konzerthaus-Café, ermäßigte Programmhefte). Der Code wird erst in der App
-- angezeigt, wenn Plus aktiv ist; die Beschreibung ist für alle sichtbar.
create table if not exists public.partner_offers (
  id uuid primary key default gen_random_uuid(),
  partner_name text not null,
  title text not null,
  description text,
  code text,
  url text,
  venue_id uuid references public.venues(id) on delete set null,
  region_id uuid references public.regions(id) on delete set null,
  valid_until date,
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.partner_offers enable row level security;
create policy "Alle lesen aktive Partnerangebote" on public.partner_offers
  for select using ((active and (valid_until is null or valid_until >= current_date)) or is_admin_or_editor());
create policy "Redaktion pflegt Partnerangebote" on public.partner_offers for all using (is_admin_or_editor()) with check (is_admin_or_editor());
