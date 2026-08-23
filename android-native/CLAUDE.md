# Claude Code handoff – Klangradar Android Native

Read this file before changing the Android native client.

## Objective

Build a real native Android app using Kotlin + Jetpack Compose (Material3
widgets, not Flutter's self-drawn ones), in parallel with the existing
Flutter app (`app/`) and the existing native iOS app (`ios-native/`). All
three share the same Supabase backend. Flutter, the Android build inside
`app/`, the backend, admin portal and scraping pipeline must remain intact.

This exists because Flutter renders its own UI on every platform (Skia/
Impeller) — it does not and cannot use real platform widgets, on Android or
iOS. `ios-native` is a from-scratch native Swift/SwiftUI app for exactly
that reason; `android-native` is its Kotlin/Compose counterpart, not an
extension of Flutter.

## Current state (2026-08-21, foundation pass)

- Gradle project scaffold: Kotlin DSL, AGP 8.6.0, Kotlin 2.0.20, Compose
  compiler plugin, kotlinx.serialization plugin. Real Gradle wrapper
  (`./gradlew`) committed.
- `applicationId`/Kotlin package `de.klangradar.android` (deliberately not
  `de.klangradar.native` like the iOS bundle id — `native` is a Java/Kotlin
  keyword and can't be used as a package segment).
- `minSdk = 26` (chosen so `java.time` works without core-library
  desugaring), `targetSdk`/`compileSdk = 35`.
- Manual Supabase REST client (`core/network/SupabaseRestClient.kt`,
  OkHttp-based) — deliberately hand-rolled like ios-native's own
  `SupabaseRESTClient.swift`, not the `supabase-kt` SDK, so both native
  clients are easy to compare request-shape-for-request-shape.
- Auth (`core/auth/`): `AuthRepository` mirrors ios-native's
  `AuthService.restoreOrCreateSession()` exactly, including the
  refresh-token **request-deduplication fix** for the "permanent lockout
  after logout" bug fixed earlier on iOS (concurrent callers share one
  in-flight refresh instead of each consuming the same one-time refresh
  token). Session persisted via `EncryptedSharedPreferences`
  (`SessionStore.kt`) — the Keystore-backed equivalent of iOS's Keychain
  store. `signInAnonymously`, `signUp`, `signInWithPassword`,
  `requestPasswordReset`, `signOut` (never truly logs out — always falls
  back to a fresh anonymous session, same as `RootTabView`'s iOS
  behavior).
- Domain model (`domain/model/ConcertEvent.kt`): field-for-field mirror of
  ios-native's `ConcertEvent.swift` — same snake_case JSON keys, same
  venue/genre/participant embed shapes.
- `data/repository/EventRepository.kt`: `upcomingEvents(limit)` — the exact
  same PostgREST `select`/filter/order string as ios-native's
  `EventRepository.upcomingEvents`.
- `data/repository/UserRepository.kt`: `recommendedEvents`/
  `discoveryEvents`/`popularEvents` — same RPC names/param
  (`p_result_limit`) as iOS, including the same row-patching (`venues.id`
  falling back to `venue_id`, missing `status` defaulting to
  `"scheduled"`).
- 5-tab bottom navigation (`ui/navigation/`), same order as
  `RootTabView.swift`: Home, Suche, Karte, Kalender, Profil — real
  Material3 `NavigationBar`/`Scaffold`/`NavHost` (Navigation-Compose).
- **Home** (`ui/home/`) is the only fully wired screen: bootstraps a
  session, fetches `upcomingEvents` + the three RPC modules in parallel,
  renders them as self-hiding `EventRail`s (a title + horizontal
  `LazyRow` of Material3 `Card`s with Coil `AsyncImage`) — the Compose
  equivalent of iOS's `EventRail`/`HeroEventView`.
- Search/Map/Kalender are plain placeholder screens (just a `TopAppBar` +
  "Noch nicht implementiert"). Profil shows auth state + sign-out but has
  no onboarding, password login UI, Face ID, or personal-data editing yet.
- Material3 theme (`ui/theme/`) reuses ios-native's brand accent
  `#146194` (`KlangradarTheme.swift`'s default) for both light/dark
  `ColorScheme`s. No Liquid-Glass equivalent attempted — Compose has
  nothing comparable; plain Material3 `Card`/`Surface` elevation is used
  instead. Default system font (Roboto) — no custom typeface, matching
  iOS's implicit SF Pro system-font choice.
- Launcher icon is a placeholder vector glyph (`res/drawable/
  ic_launcher_foreground.xml`) — not the real app icon.
- **Verified, not just written**: this pass included fetching a real
  Android SDK (cmdline-tools, platform 35, build-tools 35.0.0) into the
  sandbox and running `./gradlew :app:assembleDebug` to a genuine
  `BUILD SUCCESSFUL`, producing a real `app-debug.apk`. Two real compiler
  errors were caught and fixed this way (a `CompletableDeferred` type-
  inference bug in the refresh-dedup logic, and missing
  `@OptIn(ExperimentalMaterial3Api::class)` on every screen using
  `TopAppBar`). No emulator/device run has happened — only compile +
  package verification, not "does this actually render and work at
  runtime" (see Next recommended feature).

## Non-negotiable constraints

1. Do not modify or delete the Flutter client (`app/`) or `ios-native/`
   unless the user explicitly asks.
2. Do not commit or push unless the user explicitly asks.
3. Preserve unrelated dirty-worktree changes.
4. Never commit `local.properties`, API keys, sessions or user data.
5. Use the existing Supabase schema; do not invent replacement backend
   fields, tables, or RPCs.
6. Add migration work feature-by-feature and record it in
   `MIGRATION_STATUS.md`, mirroring `ios-native/MIGRATION_STATUS.md`'s
   dated-entry format.
7. Every migrated feature needs at least a compile-verified build
   (`./gradlew :app:assembleDebug`) before being marked done, and ideally
   a real emulator/device run once one is available in the working
   environment.
8. Keep parity in mind: before building a screen, read the corresponding
   Flutter (`app/lib/features/...`) and iOS (`ios-native/KlangradarNative/
   Features/...`) implementations first, plus the relevant `docs/*.md`.

## Workflow for every continuation

1. Run `git status --short` and do not touch unrelated files.
2. Read the corresponding Flutter and ios-native features + `docs/`.
3. Add/update Kotlin domain models and repository contracts first,
   keeping the exact same JSON field names/RPC names as ios-native.
4. Implement the Compose screen with real Material3 widgets (no custom
   look-alike components — that defeats the entire point of this app).
5. Wire it to the live repository (no separate "preview mode" data layer
   exists yet — `KlangradarApp.isUsingPreviewData` currently only gates a
   plain "not configured" message, unlike iOS's full sample-data
   fallback; build one if it becomes worth the effort).
6. Add tests where practical.
7. Run `./gradlew :app:assembleDebug` (and `:app:testDebugUnitTest` once
   tests exist) — do not mark anything "done" without this passing.
8. Update `MIGRATION_STATUS.md` with exact completed/pending behavior,
   same dated-entry format as `ios-native/MIGRATION_STATUS.md`.

## Commands

```bash
cd android-native
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
./gradlew :app:lint
```

An Android SDK is required (`ANDROID_HOME`/`sdk.dir` in
`local.properties`). If this sandbox doesn't have one on a future session,
it can be fetched directly (no Android Studio needed):

```bash
curl -fsSL -o cmdline-tools.zip \
  "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
unzip -q cmdline-tools.zip -d /opt/android-sdk/cmdline-tools_extract
mkdir -p /opt/android-sdk/cmdline-tools/latest
mv /opt/android-sdk/cmdline-tools_extract/cmdline-tools/* /opt/android-sdk/cmdline-tools/latest/
yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/opt/android-sdk \
  "platform-tools" "platforms;android-35" "build-tools;35.0.0"
echo "sdk.dir=/opt/android-sdk" > android-native/local.properties
```

## Backend configuration

`SUPABASE_URL`/`SUPABASE_ANON_KEY` are read from `local.properties`
(gitignored) into `BuildConfig` fields — see `app/build.gradle.kts` and
`local.properties.example`. Never read, print or paste real credentials
into chat output, source code, or build logs.

There is no `import_flutter_env.rb`-equivalent script yet (ios-native has
one for its `Secrets.plist`); worth adding once this project is being
actively developed on a real machine.

## Next recommended feature

All core screens (Home, Suche, Karte, Kalender, Profil incl. password
auth/Favoriten/Follows/Interessen) are now wired against live repositories
— see `MIGRATION_STATUS.md`'s 2026-08-23 entry for exactly what's covered
and what isn't. In priority order from here:

1. **Run the app on a real emulator/device** — every pass so far only got
   as far as `assembleDebug`; Compose runtime behavior (scrolling, image
   loading, navigation transitions, dark mode, TalkBack, tablet layout)
   is completely unverified. Nothing should move to ✅ in
   `MIGRATION_STATUS.md` until this happens.
2. **Entity detail screens** (person/ensemble/venue/work) — the single
   biggest structural gap. Without these, search results and followed
   entities are dead ends, and there's no natural place for a "Folgen"
   button. Read `ios-native/KlangradarNative/Features/Directory/
   EntityDetailView.swift` first.
3. Push notifications — blocked on the user providing Firebase/FCM
   credentials (a `google-services.json` or equivalent); ask before
   attempting, don't invent placeholder credentials.
4. A full interactive map — blocked on a Google Maps API key from the
   user; the current venue-list-with-`geo:`-intent fallback works without
   one and should stay as the fallback if a key never arrives.
5. Onboarding flow, Sign in with Apple/Google, biometric unlock, personal
   data editing (name/birthday/avatar/phone/address) — mirror the
   onboarding redesign already shipped in Flutter and ios-native (see
   their `MIGRATION_STATUS.md`/`CLAUDE.md` history).
6. A real preview/sample-data fallback (`KlangradarApp.isUsingPreviewData`
   currently only shows a "not configured" message instead of iOS's full
   `PreviewEventRepository` equivalent) so the app is demoable without
   secrets.
7. Real app icon (current one is a placeholder vector glyph) and a launch
   splash screen.
