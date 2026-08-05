-- Phase A.4 (docs/09-feature-expansion-plan.md): "interessiert" vs. "besuche
-- ich" statt eines rein binären Herzens — Nutzerwunsch aus der 15-Punkte-
-- Liste (Punkt 1, "Persönlicher Konzertkalender"). Default 'interested',
-- damit das bestehende Herz-Tippen (favorite_button.dart) unverändert
-- weiterfunktioniert — "besuche ich" ist eine bewusste Zusatzentscheidung,
-- kein automatischer Zustand.
alter table favorites add column status text not null default 'interested'
  check (status in ('interested', 'attending'));
