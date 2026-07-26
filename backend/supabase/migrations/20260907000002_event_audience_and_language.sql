-- Nutzeranfrage (Konzert-Detailseiten): "Zielgruppe" und "Sprache/
-- Übertitel" — beide fehlten als eigene Felder, wurden bisher höchstens
-- unstrukturiert in description_de erwähnt.
alter table events add column target_audience text;
alter table events add column performance_language text;
