-- Ticket Intelligence (Nutzeranfrage): "Mehrere Ticketanbieter pro Event
-- unterstützen". event_ticket_links (20260819000008) konnte das schon
-- schemaseitig, aber der Sync-Trigger (20260828000001) hielt die Tabelle
-- bewusst als 1:1-Spiegel von events.ticket_url — siehe dessen eigener
-- Kommentar: "das wäre ein rein additiver nächster Schritt". Das hier ist
-- dieser Schritt.
--
-- is_primary unterscheidet die automatisch aus events.ticket_url
-- abgeleitete Zeile (weiterhin vom Trigger verwaltet, 1 pro Event) von
-- manuell im Admin ergänzten zusätzlichen Anbietern (is_primary = false,
-- vom Trigger nie angefasst — sonst würden Redaktions-Ergänzungen bei der
-- nächsten Event-Bearbeitung verschwinden).
alter table event_ticket_links add column if not exists is_primary boolean not null default false;
update event_ticket_links set is_primary = true where is_primary = false;

create or replace function sync_event_ticket_link() returns trigger
language plpgsql
as $$
declare
  v_domain text;
  v_provider_id uuid;
begin
  if new.ticket_url is null then
    delete from event_ticket_links where event_id = new.id and is_primary;
    return new;
  end if;

  v_domain := lower(regexp_replace(new.ticket_url, '^(?:https?://)?(?:www\.)?([^/]+).*$', '\1'));
  if v_domain = '' or v_domain = new.ticket_url then
    delete from event_ticket_links where event_id = new.id and is_primary;
    return new;
  end if;

  insert into ticket_providers (name, domain)
    values (v_domain, v_domain)
    on conflict (domain) do nothing;
  select id into v_provider_id from ticket_providers where domain = v_domain;

  -- Nur die primäre Zeile pflegen — manuell ergänzte Zusatz-Anbieter
  -- (is_primary = false) bleiben unangetastet.
  delete from event_ticket_links
    where event_id = new.id and is_primary and url is distinct from new.ticket_url;
  insert into event_ticket_links (event_id, ticket_provider_id, url, price_min, price_max, currency, is_primary)
    values (new.id, v_provider_id, new.ticket_url, new.price_min, new.price_max, coalesce(new.price_currency, 'EUR'), true)
    on conflict (event_id, url) do update set
      ticket_provider_id = excluded.ticket_provider_id,
      price_min = excluded.price_min,
      price_max = excluded.price_max,
      currency = excluded.currency,
      is_primary = true;

  return new;
end;
$$;

-- Redaktionelles Ergänzen/Entfernen zusätzlicher Anbieter — Domain-
-- Herleitung dieselbe wie im Trigger, damit "muenchenticket.de" nicht
-- doppelt (einmal vom Trigger, einmal manuell mit leicht anderer
-- Schreibweise) als zwei ticket_providers-Zeilen landet.
create or replace function admin_add_ticket_link(
  p_event_id uuid, p_url text, p_price_min numeric default null,
  p_price_max numeric default null, p_currency text default 'EUR'
) returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_domain text;
  v_provider_id uuid;
begin
  if not is_admin_or_editor() then
    raise exception 'Nur Redaktion darf Ticketanbieter verwalten.';
  end if;

  v_domain := lower(regexp_replace(p_url, '^(?:https?://)?(?:www\.)?([^/]+).*$', '\1'));
  if v_domain = '' or v_domain = p_url then
    raise exception 'Konnte keine Domain aus der URL ableiten.';
  end if;

  insert into ticket_providers (name, domain) values (v_domain, v_domain)
    on conflict (domain) do nothing;
  select id into v_provider_id from ticket_providers where domain = v_domain;

  insert into event_ticket_links (event_id, ticket_provider_id, url, price_min, price_max, currency, is_primary)
    values (p_event_id, v_provider_id, p_url, p_price_min, p_price_max, coalesce(p_currency, 'EUR'), false)
    on conflict (event_id, url) do update set
      ticket_provider_id = excluded.ticket_provider_id,
      price_min = excluded.price_min,
      price_max = excluded.price_max,
      currency = excluded.currency;
end;
$$;

create or replace function admin_remove_ticket_link(p_event_id uuid, p_url text) returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not is_admin_or_editor() then
    raise exception 'Nur Redaktion darf Ticketanbieter verwalten.';
  end if;
  delete from event_ticket_links where event_id = p_event_id and url = p_url and not is_primary;
end;
$$;

grant execute on function admin_add_ticket_link(uuid, text, numeric, numeric, text) to authenticated;
grant execute on function admin_remove_ticket_link(uuid, text) to authenticated;
