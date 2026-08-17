-- Nutzeranfrage: "man kann personen noch nicht folgen, da das nicht
-- gespeichert wird. außerdem soll man die möglichkeit haben, bei personen,
-- ensembles, venues benachrichtigungen einzustellen." Die Speicherung
-- selbst funktionierte bereits (user_favorite_persons/_ensembles/_venues,
-- InterestsService.toggle) — es fehlte nur ein "Folgen"-Button auf den
-- Detailseiten (siehe Flutter-Änderungen). Diese Migration ergänzt die pro
-- Entität einstellbaren Benachrichtigungen, die es bisher nur als EINEN
-- globalen Schalter gab (notification_preferences.followed_ensemble_new_event).
alter table user_favorite_persons add column if not exists notify_new_events boolean not null default true;
alter table user_favorite_ensembles add column if not exists notify_new_events boolean not null default true;
alter table user_favorite_venues add column if not exists notify_new_events boolean not null default true;
