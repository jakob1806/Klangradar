-- Abschnitt 4/8: bisher gab es außer enum-artigen status-Checks keine
-- CHECK-Constraint für zeitliche Plausibilität auf events — eine Quelle
-- mit fehlerhaftem end_datetime (z.B. vertauschte Felder beim Parsen)
-- hätte das unbemerkt in die DB geschrieben. Vor dieser Migration per
-- Read-Only-Abfrage gegen die Live-DB geprüft: 0 verletzende Zeilen unter
-- den aktuell 400 Events, deshalb direkt scharf geschaltet statt NOT VALID.
alter table events
  add constraint events_end_after_start_check
  check (end_datetime is null or end_datetime >= start_datetime);
