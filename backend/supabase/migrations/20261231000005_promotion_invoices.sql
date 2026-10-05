-- Rechnungen für bezahlte Promotionen (§ 14 UStG): fortlaufende
-- Rechnungsnummer, Aussteller- und Empfängerangaben als unveränderlicher
-- Snapshot, Netto/USt/Brutto aus dem tatsächlich bei Stripe gezahlten Betrag.

-- Stammdaten des Rechnungsstellers (eine Zeile). Steuernummer/USt-IdNr., IBAN
-- und Steuerstatus müssen vom Betreiber gepflegt werden — solange sie fehlen,
-- stellt issue_promotion_invoice() bewusst keine Rechnung aus.
create table invoice_settings (
  id integer primary key default 1 check (id = 1),
  issuer_name text not null,
  issuer_street text not null,
  issuer_zip text not null,
  issuer_city text not null,
  issuer_country text not null default 'Deutschland',
  tax_number text,
  vat_id text,
  iban text,
  bic text,
  email text,
  phone text,
  small_business boolean not null default false,
  vat_rate numeric(5, 2) not null default 19.00 check (vat_rate >= 0 and vat_rate <= 30),
  updated_at timestamptz not null default now()
);

insert into invoice_settings (issuer_name, issuer_street, issuer_zip, issuer_city, email)
values ('Jakob Liess', 'Gabelsbergerstraße 6', '80333', 'München', 'jakob@klangradar.com');

alter table invoice_settings enable row level security;
create policy "Rechnungsstammdaten lesbar" on invoice_settings for select to authenticated using (true);
create policy "Redaktion pflegt Rechnungsstammdaten" on invoice_settings
  for all using (is_admin_or_editor()) with check (is_admin_or_editor());

-- Rechnungsanschrift des Zahlers (privat, nur eigene Zeile).
create table billing_profiles (
  user_id uuid primary key references profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 200),
  street text not null check (char_length(street) between 1 and 200),
  zip text not null check (char_length(zip) between 1 and 20),
  city text not null check (char_length(city) between 1 and 120),
  country text not null default 'Deutschland',
  vat_id text,
  updated_at timestamptz not null default now()
);

alter table billing_profiles enable row level security;
create policy "Nutzer verwaltet eigene Rechnungsanschrift" on billing_profiles
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Redaktion sieht Rechnungsanschriften" on billing_profiles
  for select using (is_admin_or_editor());

create table invoice_counters (
  year integer primary key,
  last_number integer not null default 0
);
alter table invoice_counters enable row level security;

create table promotion_invoices (
  promotion_id uuid primary key references event_promotions(id) on delete restrict,
  invoice_number text not null unique,
  issued_on date not null default current_date,
  paid_at timestamptz,
  service_from timestamptz,
  service_to timestamptz,
  description text not null,
  net_cents integer not null,
  vat_cents integer not null,
  gross_cents integer not null,
  vat_rate numeric(5, 2) not null,
  small_business boolean not null,
  issuer jsonb not null,
  recipient jsonb not null,
  created_at timestamptz not null default now()
);

alter table promotion_invoices enable row level security;

create function can_access_promotion_invoice(p_promotion_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from event_promotions p
    where p.id = p_promotion_id
      and (
        p.requested_by = auth.uid()
        or has_event_capability(p.event_id, 'finances')
        or has_event_capability(p.event_id, 'promotions')
        or is_admin_or_editor()
      )
  );
$$;

create policy "Berechtigte sehen Rechnungen" on promotion_invoices
  for select using (can_access_promotion_invoice(promotion_id));

-- Stellt die Rechnung zur bezahlten Promotion aus (idempotent: bei erneutem
-- Aufruf kommt die bestehende Rechnungsnummer zurück).
create function issue_promotion_invoice(p_promotion_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  promo event_promotions%rowtype;
  existing text;
  s invoice_settings%rowtype;
  bp billing_profiles%rowtype;
  ev events%rowtype;
  v_year integer := extract(year from (now() at time zone 'Europe/Berlin'))::integer;
  v_number integer;
  v_gross integer;
  v_net integer;
  v_vat integer;
  v_label text;
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet.'; end if;
  if not can_access_promotion_invoice(p_promotion_id) then
    raise exception 'Keine Berechtigung für diese Rechnung.';
  end if;

  select invoice_number into existing from promotion_invoices where promotion_id = p_promotion_id;
  if existing is not null then return existing; end if;

  select * into promo from event_promotions where id = p_promotion_id;
  if not found then raise exception 'Promotion nicht gefunden.'; end if;
  if promo.payment_status <> 'paid' or promo.payment_amount_cents is null then
    raise exception 'Für diese Promotion liegt keine bestätigte Zahlung vor.';
  end if;

  select * into s from invoice_settings where id = 1;
  if s.tax_number is null and s.vat_id is null then
    raise exception 'Die Rechnungsstellung ist noch nicht eingerichtet (Steuernummer bzw. USt-IdNr. des Rechnungsstellers fehlt).';
  end if;
  if s.iban is null then
    raise exception 'Die Rechnungsstellung ist noch nicht eingerichtet (Bankverbindung fehlt).';
  end if;

  select * into bp from billing_profiles where user_id = promo.requested_by;
  if not found then
    raise exception 'Bitte zuerst die Rechnungsanschrift unter Finanzen hinterlegen.';
  end if;

  select * into ev from events where id = promo.event_id;

  v_gross := promo.payment_amount_cents;
  if s.small_business then
    v_net := v_gross; v_vat := 0;
  else
    v_net := round(v_gross / (1 + s.vat_rate / 100.0))::integer;
    v_vat := v_gross - v_net;
  end if;

  insert into invoice_counters (year, last_number) values (v_year, 1)
  on conflict (year) do update set last_number = invoice_counters.last_number + 1
  returning last_number into v_number;

  v_label := case promo.placement
    when 'standard' then 'Standard-Platzierung'
    when 'featured' then 'Featured-Platzierung'
    when 'local_spotlight' then 'Local-Spotlight-Platzierung'
    when 'homepage_feature' then 'Homepage-Feature'
    when 'push' then 'Push-Benachrichtigung'
    else promo.placement end;

  insert into promotion_invoices (
    promotion_id, invoice_number, paid_at, service_from, service_to, description,
    net_cents, vat_cents, gross_cents, vat_rate, small_business, issuer, recipient
  ) values (
    p_promotion_id,
    'KR-' || v_year || '-' || lpad(v_number::text, 5, '0'),
    now(), promo.starts_at, promo.ends_at,
    v_label || ' in der Klangradar-App für die Veranstaltung „' || coalesce(ev.title, 'Veranstaltung') || '“',
    v_net, v_vat, v_gross, case when s.small_business then 0 else s.vat_rate end, s.small_business,
    to_jsonb(s) - 'id' - 'updated_at',
    jsonb_build_object('name', bp.name, 'street', bp.street, 'zip', bp.zip, 'city', bp.city, 'country', bp.country, 'vat_id', bp.vat_id)
  );

  return 'KR-' || v_year || '-' || lpad(v_number::text, 5, '0');
end;
$$;

revoke all on function issue_promotion_invoice(uuid) from public, anon;
grant execute on function issue_promotion_invoice(uuid) to authenticated;
