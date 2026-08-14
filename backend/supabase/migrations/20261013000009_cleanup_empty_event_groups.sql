-- Nutzer-Meldung: "aktuell bestehen eventgruppen mit keinen terminen. dort
-- steht dann z.b. 'finding neverland' '0 termine'." — programs hat keine ON
-- DELETE CASCADE/Trigger, die die Gruppe mitlöscht, wenn ihr letztes
-- Mitglied ausgehängt oder gelöscht wird (siehe admin/src/lib/
-- event-group-cleanup.ts für den Code-Fix an den drei Stellen, die das
-- auslösen können). Einmalige Bereinigung der bereits entstandenen Leichen.
delete from programs
where id not in (
  select distinct program_id from events where program_id is not null
);
