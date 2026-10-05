-- Veranstalter können eigene, noch nicht bezahlte Promotion-Anfragen selbst
-- stornieren (bisher nur durch die Redaktion möglich). Bewusst nur für
-- Anfragen in Prüfung bzw. mit ausstehender Zahlung: Eine bereits bezahlte
-- oder aktive Promotion braucht eine Erstattung und läuft weiter über die
-- Redaktion. Der Stripe-Webhook aktiviert nur Zeilen im Status
-- payment_pending, eine stornierte Anfrage kann also nicht mehr aktiv werden.
create function cancel_promotion(p_promotion_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare promo event_promotions%rowtype;
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet.'; end if;
  select * into promo from event_promotions where id = p_promotion_id for update;
  if not found then raise exception 'Promotion nicht gefunden.'; end if;
  if not (
    promo.requested_by = auth.uid()
    or has_event_capability(promo.event_id, 'promotions')
    or is_admin_or_editor()
  ) then
    raise exception 'Keine Berechtigung für diese Promotion.';
  end if;
  if promo.status not in ('pending', 'payment_pending') or promo.payment_status <> 'unpaid' then
    raise exception 'Nur offene, noch nicht bezahlte Anfragen können storniert werden.';
  end if;
  update event_promotions set status = 'cancelled', reviewed_at = coalesce(reviewed_at, now()) where id = p_promotion_id;
end;
$$;

revoke all on function cancel_promotion(uuid) from public, anon;
grant execute on function cancel_promotion(uuid) to authenticated;
