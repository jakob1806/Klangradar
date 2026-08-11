-- Neue Connector-Typen getrennt von ihrer ersten Verwendung anlegen:
-- PostgreSQL erlaubt neue Enum-Werte innerhalb derselben Migration/
-- Transaktion noch nicht zuverlässig in INSERT-Ausdrücken zu verwenden.

alter type source_type add value if not exists 'staatsoper';
alter type source_type add value if not exists 'gaertnerplatz';
