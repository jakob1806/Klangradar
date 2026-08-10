-- Zwei am 09.08.2026 über das Vercel-Adminformular gespeicherte Termine
-- wurden durch die bisherige UTC-Interpretation von datetime-local jeweils
-- um exakt zwei Stunden nach hinten verschoben. Auf den letzten vor dem
-- fehlerhaften Speichern protokollierten UTC-Wert zurücksetzen.
update events
set start_datetime = '2027-06-28T17:00:00Z', updated_at = now()
where id = 'fae1edcc-b71a-4f7e-a489-6e97f5acfded'
  and start_datetime = '2027-06-28T21:00:00Z';

update events
set start_datetime = '2026-09-18T17:30:00Z', updated_at = now()
where id = '016bd554-d049-4093-9026-bfb8c03cc2cc'
  and start_datetime = '2026-09-18T19:30:00Z';
