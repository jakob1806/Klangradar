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
- 🟡 Search, Karte, Kalender: plain placeholder screens only
  (`TopAppBar` + "Noch nicht implementiert").
- 🟡 Profil: shows auth state (anonymous/authenticated) and a sign-out
  button; no onboarding flow, no password login/signup UI, no personal
  data editing, no Face ID/biometric equivalent, no interests/follows/
  favorites screens.
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
- ⬜ No feature parity yet for: Search, Karte/map (venue map, location),
  Kalender (event calendar), Favoriten, Follows (persons/ensembles/
  venues), Interessen, Benachrichtigungen/push, onboarding, Sign in with
  Apple/Google, biometric unlock, admin/editorial features (native apps
  don't have an editorial tab at all — that's admin-web-only).

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
