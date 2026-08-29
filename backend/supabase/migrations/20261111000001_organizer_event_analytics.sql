-- Veranstalter-Portal Phase 6: Marketing Center & Analytics.
-- Die App sammelt diese Signale bereits für Empfehlungen. Diese RPC gibt sie
-- ausschließlich als Summen für Events zurück, für deren Veranstalter der
-- eingeloggte Nutzer einen genehmigten Claim hat. Es werden keine Profile,
-- Altersangaben, Standorte oder Einzelereignisse offengelegt.
create function organizer_event_analytics(p_days int default 30)
returns table (
  event_id uuid,
  event_title text,
  start_datetime timestamptz,
  views bigint,
  saves bigint,
  shares bigint,
  ticket_clicks bigint,
  avg_view_duration_seconds numeric
)
language sql
security definer
set search_path = public
stable
as $$
  select
    e.id,
    e.title,
    e.start_datetime,
    coalesce(v.views, 0)::bigint,
    coalesce(f.saves, 0)::bigint,
    coalesce(s.shares, 0)::bigint,
    coalesce(t.ticket_clicks, 0)::bigint,
    v.avg_duration
  from events e
  left join lateral (
    select count(*)::bigint as views, avg(duration_seconds)::numeric as avg_duration
    from event_views
    where event_id = e.id
      and viewed_at >= now() - make_interval(days => greatest(1, least(p_days, 365)))
  ) v on true
  left join lateral (
    select count(*)::bigint as saves
    from favorites
    where event_id = e.id
      and created_at >= now() - make_interval(days => greatest(1, least(p_days, 365)))
  ) f on true
  left join lateral (
    select count(*)::bigint as shares
    from event_shares
    where event_id = e.id
      and shared_at >= now() - make_interval(days => greatest(1, least(p_days, 365)))
  ) s on true
  left join lateral (
    select count(*)::bigint as ticket_clicks
    from ticket_clicks
    where event_id = e.id
      and clicked_at >= now() - make_interval(days => greatest(1, least(p_days, 365)))
  ) t on true
  where has_approved_organizer_event(e.id)
  order by e.start_datetime desc;
$$;

grant execute on function organizer_event_analytics(int) to authenticated;
