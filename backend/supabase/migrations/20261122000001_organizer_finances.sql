-- Der tatsächlich berechnete Betrag wird bei checkout.session.completed aus
-- Stripe übernommen. Preise werden so auch nach einer Produktpreisänderung
-- korrekt historisch ausgewiesen.
alter table event_promotions
  add column if not exists payment_amount_cents integer,
  add column if not exists payment_currency text;

alter table event_promotions
  add constraint event_promotions_payment_amount_nonnegative
  check (payment_amount_cents is null or payment_amount_cents >= 0);
