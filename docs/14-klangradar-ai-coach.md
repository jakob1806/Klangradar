# Klangradar AI Coach

Der Klangradar Coach übernimmt die Produktlogik eines datenbasierten Coaches, ohne WHOOPs Gesundheitswerte oberflächlich umzubenennen. Er arbeitet mit drei transparenten Linsen:

- **Passung:** bestätigte Interessen, gefolgte Personen/Ensembles/Werke/Venues und starke Intent-Signale wie Ticket- oder Kalenderaktionen.
- **Kulturrhythmus:** gespeicherte, geplante und reflektierte Konzertbesuche sowie persönliche Ziele.
- **Entdeckung:** Verhältnis aus vertrauten und neuen Genres, Werken, Spielstätten und Künstler:innen.

Es gibt keinen scheinpräzisen universellen „Kultur-Score“. Jede Aussage nennt Datengrundlage und Signalqualität.

## WHOOP-Funktion → Klangradar-Funktion

| WHOOP Coach | Klangradar Coach |
| --- | --- |
| Biometrie erklären | Geschmacksprofil, Empfehlungen und Kulturrhythmus erklären |
| Tages-/Trainingsplanung | Konzertabend, Wochenende oder Kulturmonat nach Zeit, Budget, Stimmung und Begleitung planen |
| Proaktive Check-ins | Hinweise zu bevorstehenden Favoriten, wenigen Tickets, Reflexionen und Zielen |
| Lifestyle-Journal | freiwilliger Check-in und Konzertreflexion mit Stimmung, Energie, Begleitung und Tags |
| Behavior Trends | Zusammenhänge zwischen Begleitung/Tags und Bewertung bzw. Energieveränderung, erst ab mindestens drei Beobachtungen |
| My Memory | einzeln sichtbare und löschbare, vom Nutzer bestätigte Erinnerungen |
| Deep Links | echte Event-, Ticket-, Venue- und Coach-Aktionen |

## Architektur

1. **Datenschicht:** bestehende Interessen, Follows, Favoriten, Ansichten, Ticketklicks und Kalenderaktionen plus `coach_checkins`, `coach_event_reflections`, `coach_goals` und `coach_memory_items`.
2. **Deterministische Synthese:** `coach_context_snapshot()`, `coach_behavior_trends()` und `coach_search_events()` berechnen belegbare Fakten und ausschließlich echte Eventtreffer.
3. **Sprachmodell:** die bestehende Provider-Fallback-Kette strukturiert Absicht/Filter und formuliert kurze Antworten. Das Modell erhält keinen freien Datenbankzugriff.
4. **Memory-Sicherheit:** neue Erinnerungen und Ziele erscheinen als Vorschlag und werden erst nach Nutzerbestätigung gespeichert.
5. **Output:** Antwort, Evidenz, echte Events, nächste Aktionen und Deep Links. Bei geringer Datenbasis sagt der Coach ausdrücklich, dass er die Person noch kennenlernt.

## Rollout

1. Migration `backend/supabase/migrations/20261202000001_klangradar_ai_coach.sql` anwenden.
2. Edge Function `backend/supabase/functions/klangradar-coach` deployen.
3. Mindestens einen Provider der bestehenden KI-Kette konfigurieren:
   - `GEMINI_API_KEY`, oder
   - `CEREBRAS_API_KEY`, oder
   - die in `_shared/ai/router.ts` konfigurierte NVIDIA-Variable.

Ohne KI-Provider bleiben Dashboard, Check-in, proaktive Karten, transparente Linsen, echte Eventsuche und ein regelbasierter deutscher Chat-Fallback funktionsfähig. Die sprachliche Interpretation komplexer Folgefragen ist dann eingeschränkt.

## Datenschutz und Aussagegrenzen

- Alle Coach-Tabellen verwenden RLS und sind nur für den jeweiligen Nutzer zugänglich.
- Check-ins und Reflexionen sind freiwillig.
- Verhaltenstrends werden erst ab drei Beobachtungen gezeigt und ausdrücklich als Zusammenhang, nicht als Ursache, formuliert.
- Das Sprachmodell erhält einen begrenzten Kontext-Snapshot statt unbeschränkter Rohdaten.
- Erinnerungen und Ziele werden nicht heimlich aus normaler Konversation übernommen.
- Eventnamen und Empfehlungen stammen ausschließlich aus der Klangradar-Datenbank.

## Noch offen

- Push-Auslieferung proaktiver `coach_insights` über die bestehende Notification-Infrastruktur.
- UI zum Bearbeiten/Löschen aller Memory-Einträge und Ziele unter „Mein Klangradar“.
- Post-Event-Reflexionssheet direkt nach besuchten Konzerten, damit Behavior Trends in der Praxis Daten erhalten.
- Optional kuratierte, zitierfähige Klassik-Wissensbasis für längere Werk-/Komponistenfragen.
