# Sicherheitsstatus vor Veröffentlichung

Stand: 2026-08-25. Ergebnis einer Sicherheitsanalyse (Auth, RLS, Secrets, Edge
Functions) vor öffentlichem Launch.

## Zusammenfassung

| Bereich | Status |
|---|---|
| Nutzeranmeldung (E-Mail-Code-Login, Anon-Bootstrap) | Solide |
| Row Level Security (78 Tabellen) | Vollständig aktiv, korrektes `SECURITY DEFINER`-Muster |
| Admin-Dashboard-Zugriffsschutz (`proxy.ts`) | Solide, kein Service-Role-Key im Client |
| Secrets im Repo | Keine gefunden (Anon-Key/Firebase-Keys sind by-design öffentlich) |
| **Edge Functions mit Service-Role-Zugriff** | **War kritische Lücke — jetzt behoben, siehe unten** |

## Behobener Fund: unautorisierter Zugriff auf privilegierte Edge Functions

35 Supabase Edge Functions liefen mit `SUPABASE_SERVICE_ROLE_KEY` (RLS-Bypass),
prüften aber selbst keine Berechtigung — nur Supabase' Standard `verify_jwt`,
das bereits der öffentliche Anon-Key erfüllt (im App-Bundle, in
`admin/.env.local.example`, vormals auch im Klartext in den Cron-Migrationen).
Damit konnte jede Person mit dem Anon-Key diese Functions beliebig oft mit
vollem Service-Role-Zugriff aufrufen: Kostenabuse (LLM-/Bildsuche-Aufrufe),
Scraping-Abuse (`ingest-source`), Notification-Spam (`notify-*`), ungewollte
Schreibzugriffe (`resolve-*`, `repair-*`, `backfill-*`).

**Fix:**
- `backend/supabase/functions/_shared/internalAuth.ts` — neuer Guard
  `requireInternalAuth()`, in alle 35 betroffenen Functions als erste Zeile
  im Handler eingebaut. Autorisiert entweder (a) einen eingeloggten
  Admin/Editor-Nutzer (Bearer-Token wird gegen `is_admin_or_editor()`
  geprüft — dasselbe Muster wie `editorial-ai-assistant`, das schon vorher
  korrekt war) oder (b) ein gemeinsames Secret im Header
  `x-internal-secret` für nicht-nutzergebundene Aufrufer (Cron, Admin-
  Server-Actions ohne Nutzersession).
- Admin-Dashboard: alle Server-Actions, die diese Functions mit dem
  Anon-Key aufrufen (9 Dateien), senden jetzt zusätzlich
  `x-internal-secret` aus der server-only Env-Var `INTERNAL_FUNCTION_SECRET`.
- Datenbank: `backend/supabase/migrations/20261029000002_internal_function_secret_for_cron.sql`
  liest das Secret aus Supabase Vault (`internal_function_secret()`,
  `SECURITY DEFINER`) und ergänzt es in allen 31 Cron-Functions, die per
  `net.http_post` eine dieser Edge Functions aufrufen.

**[MANUELLER SCHRITT VOR DEPLOY — nicht aus dem Repo heraus möglich, da das
Secret an drei Stellen synchron gesetzt werden muss]:**

1. Zufälliges Secret erzeugen: `openssl rand -hex 32`
2. In Supabase Vault hinterlegen (SQL Editor):
   `select vault.create_secret('<wert>', 'internal_function_secret');`
3. Als Edge-Function-Secret setzen: `supabase secrets set INTERNAL_FUNCTION_SECRET=<wert>`
4. Als Server-Env-Var im Admin-Dashboard-Hosting setzen (Next.js Server
   Action, ohne `NEXT_PUBLIC_`-Prefix): `INTERNAL_FUNCTION_SECRET=<wert>`

Bis Schritt 1-2 erfolgt sind, liefert `internal_function_secret()` `NULL`,
die Cron-Jobs laufen dadurch leer (kein Crash, siehe deren
`raise warning`-Fehlerbehandlung), bis das Secret gesetzt ist.

## Bereits korrekt (keine Änderung nötig)

- `editorial-ai-assistant`, `audit-entity`, `audit-entities-bulk`,
  `backfill-work-image-reuse`: prüfen bereits eigenständig
  `is_admin_or_editor()` vor Service-Role-Zugriff.
- `admin/.../image-research/actions.ts`: reicht bereits den echten
  User-Access-Token durch (nicht den Anon-Key) — wird vom neuen Guard über
  den Nutzer-Pfad automatisch mitautorisiert.
- Funktionen ohne `SUPABASE_SERVICE_ROLE_KEY` (`probe-source`,
  `parse-event-participants`) — kein RLS-Bypass, daher kein Fund.

## Offen / nicht Teil dieser Änderung

- Supabase-Auth-Ratelimits für E-Mail-Code-Login in Produktion prüfen
  (Supabase-Dashboard-Einstellung, kein Code-Fix).
