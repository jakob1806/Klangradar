-- Nutzerwunsch: "bei den eventgruppen soll man mehrere auswählen können und
-- diese direkt entweder ablehnen oder als gruppe anlegen lassen" — ein
-- abgelehntes Event darf beim nächsten Laden von suggestEventGroups() nicht
-- wieder als Vorschlag auftauchen. Die Vorschläge selbst sind rein
-- berechnet (kein eigener Tabellen-Zustand), daher reicht ein einzelner
-- Zeitstempel direkt auf events: gesetzt = "wurde als Serie abgelehnt,
-- nicht erneut vorschlagen", unabhängig davon, ob das Event später
-- trotzdem manuell einer Gruppe hinzugefügt wird (dort bleibt es
-- weiterhin möglich, siehe addEventToGroup()).
alter table events add column if not exists group_suggestion_dismissed_at timestamptz;
