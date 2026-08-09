# Claude Code handoff – Klangradar Native

Read this file before changing the native client.

## Objective

Build an iPhone/iPad SwiftUI client in parallel with the existing Flutter app.
The native client must eventually reach feature parity, but the Flutter app,
Android app, backend, admin portal and scraping pipeline must remain intact.

## Current state

- Independent SwiftUI app target for iPhone and iPad.
- Native `TabView` with Home, Search, Map, Calendar and Profile.
- Native Liquid Glass on iOS 26+, material fallback on iOS 17–25.
- Dependency-injected event and content repositories.
- Supabase PostgREST reads/writes, RPC support, anonymous/email-OTP auth and
  Keychain session persistence.
- Preview-data fallback when no local configuration exists.
- Live global search and directories/details for persons, ensembles, venues
  and works, including biography, gallery and linked-event data.
- Editorial collections, live venue map data, favorite-event reads and live
  notification preferences.
- The local ignored `Config/Secrets.plist` has been imported from Flutter on
  this machine. Live simulator builds therefore use the shared Supabase data.
- Event lists bulk-resolve licensed gallery fallbacks from the
  `ingested-images` bucket when an event has no own image.
- Unit tests for Supabase-shaped event decoding and preview data.
- The 2026-08-09 detail/navigation batch is implemented: compact Home artwork,
  edge-swipe dismissal, circular related-person/ensemble carousels, image-first
  venue details, grouped/collapsed venue dates, redesigned calendar rows,
  linked event navigation, text-only work presentation and a persistent ticket
  action. See `MIGRATION_STATUS.md` for the exact #1–#10 checklist.
- Home hero copy is intentionally rendered directly over a controlled bottom
  gradient. Do not restore the former near-full-width glass panel; it obscured
  the artwork and made long titles look detached from the image.
- Event detail now requests structured works/participants, inherits missing
  repeated-program content from the richest sibling date, and falls back from
  `ticket_url` to the official `website_url` without fabricating program data.
- Event composers, participants and venues now expose native navigation links;
  participant/search thumbnails bulk-resolve licensed gallery fallbacks. Never
  restore the synthetic `Preis auf Anfrage` copy: absent price fields mean that
  no price label is rendered.
- Program audit on 2026-08-09 found 252/386 upcoming events with structured
  works. The unapplied migration
  `../backend/supabase/migrations/20261007000003_requeue_missing_event_programs.sql`
  requeues only source-backed scheduled events without `event_works`; deploy it
  deliberately, then let the existing enrichment cron drain the batch.

## Non-negotiable constraints

1. Do not modify or delete the Flutter client unless the user explicitly asks.
2. Do not commit or push unless the user explicitly asks.
3. Preserve unrelated dirty-worktree changes.
4. Never commit `Config/Secrets.plist`, API keys, sessions or user data.
5. Use the existing Supabase schema; do not invent replacement backend fields.
6. Add migration work feature-by-feature and record it in `MIGRATION_STATUS.md`.
7. Every migrated feature needs at least one model/repository test and one UI
   verification on iPhone and iPad.
8. Keep iOS 17 fallback behavior while using native Liquid Glass on iOS 26+.

## Workflow for every continuation

1. Run `git status --short` and do not touch unrelated files.
2. Read the corresponding Flutter feature and the relevant files in `docs/`.
3. Update or add Swift domain models and repository contracts first.
4. Implement the SwiftUI screen with preview/sample data.
5. Connect live Supabase data through an injectable repository.
6. Add tests.
7. Run the project generator if files were added.
8. Build and test for an iPhone and an iPad simulator.
9. Update `MIGRATION_STATUS.md` with exact completed and pending behavior.

## Commands

```bash
cd ios-native
ruby Scripts/generate_project.rb
xcodebuild -project KlangradarNative.xcodeproj -scheme KlangradarNative \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -project KlangradarNative.xcodeproj -scheme KlangradarNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

## Backend configuration

Prefer Xcode scheme environment variables for local work:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Alternatively use the ignored `Config/Secrets.plist`. Never read, print or
paste credentials into chat output, source code or build logs.

To import the already configured Flutter client values locally without exposing
them, run `ruby Scripts/import_flutter_env.rb` and regenerate the project.

## Next recommended feature

Harden and test the completed detail/navigation batch before adding scope:

1. Add UI tests for left-edge swipe dismissal, linked-event navigation and the
   persistent ticket action.
2. Add repository fixtures for repeated dates whose structured program exists
   only on a sibling event.
3. Run visual checks on an iPad simulator and with large Dynamic Type.
4. Then continue event provenance/content reporting and APNs registration.
