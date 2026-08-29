alter table event_promotions drop constraint event_promotions_status_check;
alter table event_promotions add constraint event_promotions_status_check check (status in ('pending', 'payment_pending', 'approved', 'rejected', 'cancelled'));
alter table event_promotions add column payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid', 'refunded'));
alter table event_promotions add column stripe_checkout_session_id text unique;
