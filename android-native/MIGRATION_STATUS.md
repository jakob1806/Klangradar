# Klangradar Android Native — Migration Status

Tracks feature parity against `app/` (Flutter) and `ios-native/` (Swift),
in the same dated-entry format as `ios-native/MIGRATION_STATUS.md`.

## Project foundation (2026-08-21, ✅ build-verified)

- ✅ Gradle/Kotlin/Compose project scaffold, real `./gradlew` wrapper,
  builds a genuine debug APK end to end (`./gradlew :app:assembleDebug` →
  `BUILD SUCCESSFUL`, verified in this pass with a real Android SDK
  fetched into the sandbox — not just written-and-hoped-for like the
  earliest ios-native passes had to be).
- ✅ Supabase REST client (`SupabaseRestClient`), matching ios-native's
  hand-rolled client's request shape (apikey/Authorization headers, same
  PostgREST/RPC/auth path conventions).
- ✅ Auth bootstrap (`AuthRepository`): anonymous-first session, Keystore-
  backed persistence (`EncryptedSharedPreferences`), refresh-token
  request deduplication (same fix as ios-native's lockout-after-logout
  bug), sign up/in with password, password reset request, sign out
  (always falls back to a fresh anonymous session).
- ✅ Domain model `ConcertEvent` + nested types, exact field/JSON-key
  parity with `ios-native/.../ConcertEvent.swift`.
- ✅ `EventRepository.upcomingEvents` — identical PostgREST select/filter/
  order to ios-native's `EventRepository.upcomingEvents`.
- ✅ `UserRepository.recommendedEvents/discoveryEvents/popularEvents` —
  identical RPC names/params to ios-native's `UserRepository`, including
  the same `venues.id`/`status` row-patching before decoding.
- ✅ 5-tab bottom navigation (Home/Suche/Karte/Kalender/Profil), same
  order as `RootTabView.swift`, real Material3 `NavigationBar`.
- ✅ **Home screen fully wired**: bootstraps a session, loads
  `upcomingEvents` + all three RPC modules in parallel, renders
  self-hiding `EventRail`s (title + horizontal `LazyRow` of Material3
  `Card`s, Coil `AsyncImage`) — the one screen built out to the same
  depth as ios-native's `HomeView` for its first pass.
- 🟡 Material3 theme reuses ios-native's `#146194` brand accent for both
  light/dark; no Liquid-Glass equivalent (Compose has none) — plain
  Material3 surfaces/elevation instead.
- ⬜ Real app icon (current one is a placeholder vector glyph).
- ⬜ No preview/sample-data fallback yet — `isUsingPreviewData` only
  shows a "not configured" message, unlike iOS's full
  `PreviewEventRepository`.
- ⬜ **Never run on an emulator or device** — this pass verified
  `compileDebugKotlin` and `assembleDebug` only. Compose layout/runtime
  behavior (scrolling, image loading, navigation transitions, dark mode,
  Dynamic Type/font-scale equivalents) is unverified.
- ⬜ No tests yet (no JVM unit tests, no instrumented UI tests).

## Core feature build-out (2026-08-23, ✅ build-verified, ⬜ never run)

Filled in every screen/repository gap that doesn't require an external
credential we don't have (Google Maps API key, Firebase project). Same
caveat as above: `compileDebugKotlin` + `assembleDebug` both pass, but
none of this has run on a device/emulator yet.

- ✅ **Suche**: `ContentRepository.search` (RPC `search_all`, same
  ensemble-visibility filtering as ios-native's `ContentRepository.search`)
  wired to a debounced search field + result list (person/ensemble/venue/
  work icons). Tapping a result currently does nothing — there is no
  entity detail screen yet on Android (see below).
- ✅ **Kalender**: `EventRepository.allUpcomingEvents` (pages through every
  upcoming event, same query as ios-native's `allUpcomingEvents`) grouped
  by day into sticky-style date headers.
- 🟡 **Karte**: `ContentRepository.venueLocations` (RPC
  `venues_with_latlng`) rendered as a sorted venue list, not an embedded
  interactive map — there is no Google Maps API key configured for this
  app (see `CLAUDE.md`). Tapping a venue opens the device's own Maps app
  via a `geo:` intent, which needs no API key and genuinely works, but is
  not the same experience as ios-native's in-app `VenueMapView`.
- ✅ **Profil — Passwort-Login/Registrierung/Reset**: a real form (not a
  placeholder) covering sign in, sign up, and "Passwort vergessen" against
  `AuthRepository`'s already-existing methods. No onboarding flow, no
  personal-data editing, no Face ID/biometric equivalent yet.
- ✅ **Favoriten**: `FollowsRepository` (`favorites` table) — a heart
  toggle directly on every Home event card (optimistic, same pattern as
  ios-native's `FavoriteStore`), plus a dedicated "Meine Favoriten" list
  reachable from Profil.
- ✅ **Follows (Personen/Ensembles/Orte)**: `FollowsRepository`
  (`user_favorite_persons`/`_ensembles`/`_venues`) — a "Meine Follows"
  screen grouped by kind, each row with a notify-toggle and "Entfolgen",
  reachable from Profil. There is no follow *button* anywhere yet (no
  entity detail screens exist to put one on) — only management of
  existing follows.
- ✅ **Interessen**: `UserRepository.genreOptions`/`selectedGenreIds`/
  `setGenreInterest` (`genres` + `profile_interest_genres` tables) — a
  toggle-list screen reachable from Profil. Work/person/venue interests
  (the other `InterestCategory` cases on iOS) aren't exposed as a
  separate UI here, same as how ios-native only surfaces genre interests
  plus follows for the rest.
- ⬜ **No entity detail screens at all** (person/ensemble/venue/work) —
  this is the single biggest remaining structural gap. Search results and
  followed entities can't be tapped through to a detail page; there's
  nowhere to put a "Folgen" button either. This is real, nontrivial work
  (biography/gallery/linked-events per entity kind) — next priority.
- ⬜ **Push notifications** — blocked on a Firebase project + FCM
  credentials this session has no access to (Flutter uses
  `firebase_messaging`); needs the user to provide a `google-services.json`
  or equivalent before this can be built.
- ⬜ **Full interactive map** — blocked on a Google Maps API key.
- ⬜ Onboarding flow, Sign in with Apple/Google, biometric unlock, personal
  data editing (name/birthday/avatar/phone/address) — none built yet.
- ⬜ Admin/editorial features are intentionally out of scope for any
  native client (Flutter's admin is a separate web app).

## Definition of feature parity

Mirrors `ios-native/MIGRATION_STATUS.md`'s bar — a row can only be marked
✅ once it:

1. matches the current Flutter behavior and backend contract,
2. has loading, empty, error and offline behavior,
3. works in light and dark theme,
4. supports phone and tablet layouts,
5. supports large font scale and TalkBack (Android's Dynamic Type/
   VoiceOver equivalents),
6. has been run on a real emulator or device, not just compiled.
