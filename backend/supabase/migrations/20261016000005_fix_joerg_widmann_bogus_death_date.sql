-- Datenfehler live gefunden (2026-08-15/16): Jörg Widmann (geb. 1973-06-19,
-- laut mehreren aktuellen 2026er-Konzertankündigungen bei Gasteig, MKO
-- aktiv als Dirigent/Solist auftretend) stand mit death_date = 0001-01-01
-- und is_deceased = true in der Datenbank. Ein bestehender Schutz-Trigger
-- verhinderte dadurch korrekt jede Verknüpfung als lebend auftretende Rolle
-- ("... ist am 0001-01-01 verstorben und kann nicht als dirigent verknüpft
-- werden") — der Trigger selbst arbeitet richtig, die zugrunde liegenden
-- Daten waren falsch.
update persons
set death_date = null,
    is_deceased = false
where id = 'd59415af-7dae-4eec-81c0-d4d87fabba96'
  and full_name = 'Jörg Widmann';

update events set gasteig_detail_synced_at = null, gasteig_detail_sync_error = null
where id = '8c29aa20-ff34-4957-b7b9-adeab3020e0b';

update events set mko_detail_synced_at = null, mko_detail_sync_error = null
where id = 'a5a9e188-9689-4259-be53-b865be852562';
