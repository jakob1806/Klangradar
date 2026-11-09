-- Wallet (09.11.2026): von der App erzeugte Bildstreifen je Karte speichern,
-- damit Aktualisierungen über wallet-service dasselbe Bild verwenden.
alter table public.wallet_passes add column if not exists strips jsonb;
