-- Erstellt von Claude Code (Portal Pro, Punkt 15 der Ausbauliste).
-- Monatsabo für Veranstalter: Kontingent an Standard-Platzierungen pro
-- Abrechnungsperiode, erweiterte Statistik, bevorzugte Prüfung.
-- Gepflegt ausschließlich vom Stripe-Webhook (Service-Rolle).

create table if not exists public.organizer_subscriptions (
  organizer_id uuid primary key references public.organizers(id) on delete cascade,
  plan text not null default 'pro',
  status text not null,
  stripe_customer_id text,
  stripe_subscription_id text unique,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.organizer_subscriptions enable row level security;

create policy "Team sieht eigenes Abo" on public.organizer_subscriptions
  for select using (has_approved_organizer_claim(organizer_id) or is_admin_or_editor());

-- Im Abo enthaltene Platzierungen werden nicht einzeln bezahlt.
alter table public.event_promotions drop constraint if exists event_promotions_payment_status_check;
alter table public.event_promotions add constraint event_promotions_payment_status_check
  check (payment_status in ('unpaid', 'paid', 'refunded', 'included'));
