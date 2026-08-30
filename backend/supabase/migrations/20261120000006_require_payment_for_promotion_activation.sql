-- Eine redaktionelle Zusage schaltet ausschließlich den Checkout frei.
-- Sichtbarkeit darf ausschließlich nach einem verifizierten Stripe-Zahlungs-
-- ereignis entstehen. Diese Sicherung liegt bewusst in der Datenbank, damit
-- weder Admin-Oberfläche noch spätere Imports die Zahlungspflicht umgehen.
update event_promotions
set status = 'payment_pending', starts_at = null, ends_at = null
where status = 'approved' and payment_status <> 'paid';

create or replace function require_paid_promotion_for_activation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'approved' and new.payment_status <> 'paid' then
    raise exception 'Eine Promotion darf erst nach bestätigter Zahlung aktiviert werden.';
  end if;
  if new.status = 'approved' and (new.starts_at is null or new.ends_at is null) then
    raise exception 'Eine aktive Promotion benötigt ein vollständiges Laufzeitfenster.';
  end if;
  return new;
end;
$$;

drop trigger if exists event_promotions_require_payment_before_activation on event_promotions;
create trigger event_promotions_require_payment_before_activation
  before insert or update on event_promotions
  for each row execute function require_paid_promotion_for_activation();

notify pgrst, 'reload schema';
