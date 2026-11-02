-- Neue Spielplan-Quellen außerhalb Münchens (Ziel: Abdeckung wie München).
-- Konfigurationen gegen die Live-Seiten getestet (2026-11-02).
insert into sources (name, type, url, venue_id, city_id, crawl_frequency_minutes, legal_basis, status, config)
select v.name, 'scrape', v.url, null, (select id from regions where type = 'city' and slug = v.city), 1440, 'Rechtlich ungeprüft (siehe docs/10-legal-status.md) — robots.txt geprüft, öffentlicher Spielplan', 'active', v.config::jsonb
from (values
  ('Konzerthaus Berlin – Programm', 'https://www.konzerthaus.de/de/programm', 'berlin',
   '{"itemSelector":"li.event-item","titleSelector":".event-title a","urlSelector":".event-title a","dateSelector":"time.event-item-info","dateAttribute":"datetime","venueSelector":".room","defaultVenueName":"Konzerthaus Berlin","baseUrl":"https://www.konzerthaus.de","nextPageSelector":"a.infinite-more-link","maxPages":12}'),
  ('Staatsoper Unter den Linden – Spielplan', 'https://www.staatsoper-berlin.de/de/spielplan/', 'berlin',
   '{"itemSelector":"div.termin","titleSelector":"h3 span","urlSelector":"h3 a","dateSelector":"time","dateAttribute":"datetime","venueSelector":".termin__spielstaette a","defaultVenueName":"Staatsoper Unter den Linden","baseUrl":"https://www.staatsoper-berlin.de","nextPageSelector":"a#next-link","maxPages":12,"titleExcludeIfContains":["Einblick","Führung","Gastspiel in"]}'),
  ('Staatsoper Hamburg – Spielplan', 'https://www.staatsoper-hamburg.de/de/spielplan/', 'hamburg',
   '{"itemSelector":"div.block--event","titleSelector":".event__title span","dateSelector":"span.event__date","timeSelector":"span.event__datetime","venueSelector":".event__location span","defaultVenueName":"Staatsoper Hamburg","baseUrl":"https://www.staatsoper-hamburg.de","titleExcludeIfContains":["Führung","Schulklassen","Sneak"]}'),
  ('Alte Oper Frankfurt – Programm', 'https://www.alteoper.de/de/programm/', 'frankfurt',
   '{"itemSelector":".event-item","titleSelector":".event-item__headline .link__text","urlSelector":".event-item__headline","dateSelector":".event-time","defaultVenueName":"Alte Oper Frankfurt","baseUrl":"https://www.alteoper.de","imageSelector":"img.image-item__img","imageAttribute":"src","titleExcludeIfContains":["Investmentfokus","Mireille Mathieu"]}')
) as v(name, url, city, config)
where not exists (select 1 from sources s where s.url = v.url);
