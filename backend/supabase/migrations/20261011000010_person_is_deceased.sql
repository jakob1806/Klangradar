-- Nutzeranfrage: "es braucht eine checkbox neben dem sterbedatum, ob die
-- person auch schon gestorben ist" — bisher war death_date IS NOT NULL das
-- einzige Signal dafür, dass eine Person verstorben ist. Das reicht nicht,
-- wenn die Redaktion zwar weiß, dass jemand verstorben ist, aber das genaue
-- Datum (noch) nicht kennt — dann blieb bisher nur, death_date leer zu
-- lassen und die Person fälschlich als lebend zu führen. is_deceased trennt
-- "verstorben (Ja/Nein)" von "an welchem Datum" und wird für alle bereits
-- bekannten Sterbedaten einmalig vorbefüllt, damit bestehende Auswertungen
-- (z.B. der prevent_deceased_live_performer-Trigger, der weiterhin ein
-- konkretes Datum für den Vergleich mit dem Event-Termin braucht) konsistent
-- bleiben.
alter table persons add column is_deceased boolean not null default false;
update persons set is_deceased = true where death_date is not null;
