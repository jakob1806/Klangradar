-- Bugfix-Nachlauf: resolvePerson()/resolveEnsembles() in
-- eventParticipantResolution.ts hatten eine Race Condition bei
-- gleichzeitig verarbeiteten Events mit derselben neuen Person/demselben
-- Hausensemble (z.B. "Jörg Widmann" bei einem Gasteig-Event, "Carolin
-- Widmann" bei einem MKO-Event fehlten trotz erfolgreicher
-- Namensauflösung in event_participants) — jetzt behoben. Setzt die zwei
-- live beobachteten betroffenen Events zurück, damit der nächste
-- Cron-Lauf sie mit dem korrigierten Code neu verarbeitet.
update events set gasteig_detail_synced_at = null, gasteig_detail_sync_error = null
where id = '8c29aa20-ff34-4957-b7b9-adeab3020e0b';

update events set mko_detail_synced_at = null, mko_detail_sync_error = null
where id = 'a5a9e188-9689-4259-be53-b865be852562';
