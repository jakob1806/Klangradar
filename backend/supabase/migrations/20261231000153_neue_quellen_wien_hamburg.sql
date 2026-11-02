-- Weitere Spielplan-Quellen Wien/Hamburg (gegen Live-Seiten getestet, 2026-11-02).
insert into sources (name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config)
select v.name, 'scrape', v.url, null, (select id from regions where type = 'city' and slug = v.city), 1440,
  'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, öffentlicher Spielplan', 'active', v.config::jsonb
from (values
  ('Symphoniker Hamburg – Konzerte', 'https://www.symphonikerhamburg.de/konzerte/', 'hamburg',
   '{"itemSelector":".calendar-item","titleSelector":"h2","urlSelector":"a.ctaWhite","dateSelector":".kDate","timeSelector":".kHour","venueSelector":".kOrt","defaultVenueName":"Laeiszhalle Hamburg","baseUrl":"https://www.symphonikerhamburg.de"}'),
  ('Wiener Symphoniker – Kalender', 'https://www.wienersymphoniker.at/kalender', 'wien',
   '{"itemSelector":"div.s-clickable-teaser","titleSelector":"a[hreflang]","urlSelector":"a[hreflang]","dateSelector":"time","dateAttribute":"datetime","venueSelector":"time + div","defaultVenueName":"Wiener Konzerthaus","baseUrl":"https://www.wienersymphoniker.at","nextPageSelector":"a[rel=next]","maxPages":8}')
) as v(name, url, city, config)
where not exists (select 1 from sources s where s.url = v.url);
