-- Erstellt von Claude Code (27.10.2026): Abo-Erkennung für BRSO repariert
-- (Text-Bereinigung verschluckte Seiten mit Inline-Skripten) und auf weitere
-- Münchner Quellen erweitert (Rundfunkorchester, BR-Chor, Münchener
-- Kammerorchester, Gärtnerplatztheater). Betroffene kommende Termine einmal
-- neu abgleichen; sync-event-subscriptions holt sie per Cron nach.
update public.events set subscriptions_synced_at = null
where start_datetime >= now()
  and (
    coalesce(website_url, '') ~* '(brso\.de|rundfunkorchester\.de|br-chor\.de|m-k-o\.eu|gaertnerplatztheater\.de)'
    or coalesce(external_id, '') ~* '(brso\.de|rundfunkorchester\.de|br-chor\.de|m-k-o\.eu|gaertnerplatztheater\.de)'
  );
