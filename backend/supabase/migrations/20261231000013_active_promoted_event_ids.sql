-- Öffentliche Liste der aktuell beworbenen Events (bezahlt, genehmigt, im
-- Buchungszeitraum). Die Apps kennzeichnen diese Kacheln klein als "Anzeige".
-- Push-Buchungen zählen nicht (keine Kachel). Liefert nur IDs, keine
-- Zahlungs- oder Anfragerdaten.
create function active_promoted_event_ids()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select distinct p.event_id
  from event_promotions p
  where p.status = 'approved'
    and p.payment_status = 'paid'
    and p.placement <> 'push'
    and p.starts_at <= now()
    and p.ends_at > now();
$$;

revoke all on function active_promoted_event_ids() from public;
grant execute on function active_promoted_event_ids() to anon, authenticated;
