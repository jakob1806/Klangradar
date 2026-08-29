-- Die Funktion ensure_profile_event_organizer_context wurde in einer
-- vorausgehenden Migration angelegt. PostgREST hält Funktionssignaturen im
-- Schema-Cache; ohne diesen Reload kann die API sie bis zum nächsten Reload
-- nicht auflösen und das Veranstalterportal würde beim Laden fehlschlagen.
notify pgrst, 'reload schema';
