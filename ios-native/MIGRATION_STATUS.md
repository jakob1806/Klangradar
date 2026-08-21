# Native migration status

Last updated: 2026-08-09

Legend: ✅ scaffolded and working · 🟡 partial · ⬜ not started

| Area | Status | Current native coverage | Next parity work |
|---|---|---|---|
| App shell | ✅ | iPhone/iPad target, five native tabs | Deep-link routing and per-tab path restoration |
| Design system | 🟡 | adaptive light/dark background, native Liquid Glass surfaces and contrast-safe fallback borders | Complete tokens, accessibility variants and snapshot tests |
| Supabase | 🟡 | local ignored configuration imported, live PostgREST reads/writes, RPCs, anonymous and email-OTP sessions | Token refresh coverage, realtime and Edge Functions |
| Home | 🟡 | live hero plus recommendation, seven-day, weekend, popularity, discovery, genre, free-entry and personalized event rails | Recommendation feedback signals and per-module analytics |
| Search | 🟡 | `search_all`, fully paginated events/directories, right-aligned counts, thumbnails and Contacts-style A–Z/# directory index | Search history and advanced filters |
| Map | 🟡 | native MapKit, selectable venues, event preview sheet, name/upcoming filters and reliable Munich recentering | Clustering, location permission flow and route mode selection |
| Calendar | 🟡 | German custom month grid, concert-day markers and image-backed daily event list | Calendar sync, evening planning and persisted selection |
| Profile | 🟡 | Supabase session/email OTP, favorites, named personal concert lists, complete interests editor and live notification preferences | Language and admin access |
| Event detail | 🟡 | resilient live full/core query, full-width artwork with overlay actions, program, participants, prices, tickets, accessibility, venue and attribution | Other dates, changes, provenance, similar events and content reporting |
| Persons | 🟡 | directory, detail, biography, gallery, linked events and similar entries | Follow toggle, provenance/reporting and field-complete layout |
| Ensembles | 🟡 | directory, detail, biography, gallery, linked events and similar entries | Follow toggle, provenance/reporting and field-complete layout |
| Venues | 🟡 | directory, detail, gallery, linked events and live map location | Venue event sheet, provenance/reporting and full metadata |
| Works | 🟡 | directory, generic metadata detail and linked performances | Dedicated composer/movement presentation |
| Collections | 🟡 | published collection rail and redesigned image-first detail with compact full-width event rows | Full empty/error states and sharing |
| Favorites | 🟡 | authenticated favorite-event read/list | Toggle, status planning and anonymous synchronization |
| Redaktion | 🟡 | rollenbeschränkter Native-Schnellkorrekturmodus im Apple-Design mit Bereichsauswahl und Live-Suche; nur heutige/zukünftige Events; Event-Titel, Untertitel, Termin, Venue, Bilder, Mitwirkende und Programm sowie Venues, Personen, Ensembles und Werke bearbeitbar; zentrale Mehrfachbilder-Galerie für Events, Venues, Personen, Ensembles und Werke mit Mehrfachauswahl aus Fotomediathek/Dateien, Titelbildwahl und Einzellöschung; Programmwerke inklusive Titel und Komponist:in direkt bearbeitbar; fehlende Personen, Ensembles und Werke sowohl zentral als auch direkt bei der Veranstaltungszuordnung neu anlegbar; direkte gemeinsame Supabase-Schreibvorgänge mit `system_logs`-Audit | Venue-Neuanlage mit Geodaten sowie erweiterte Zuschnitt-/Lizenzverwaltung bleiben im Admin-Portal |
| Interests | 🟡 | live genres/persons/ensembles/venues selection and persistence | Recommendation feedback and onboarding preselection |
| Notifications | 🟡 | all five preference fields read and upsert | APNs token registration and permission flow |
| Onboarding | 🟡 | first-run paging, notification choice and persisted completion | Inline interest/location selection |
| Localization | ⬜ | German literals only | String Catalog for German and English |
| Accessibility | 🟡 | semantic labels and native controls | Dynamic Type audit, VoiceOver, contrast and reduced motion |
| Automated tests | 🟡 | event decoding, preview repository and venue grouping (10 passing tests) | Repository fixtures, view-model tests and UI tests |

## Bug-fix batch b1–b10 (2026-08-09)

- ✅ #b1 Home hero and event-card dimensions no longer overlap.
- ✅ #b2 Complete directory counts are trailing-aligned; upcoming concert rows use matching thumbnails.
- ✅ #b3 Person, ensemble and venue base details no longer fail when optional gallery/link queries fail.
- ✅ #b4 Map markers open a venue preview with upcoming events, route and detail navigation.
- ✅ #b5 German weekday/date formatting and month concert markers are active.
- ✅ #b6 Map recenter control and venue filters are functional.
- ✅ #b7 Interests include complete, categorized and searchable genre/person/ensemble/venue lists.
- ✅ #b8 Upcoming events use pagination instead of fixed list limits (386 live records at verification time).
- ✅ #b9 Event detail artwork and overlay actions use the available display width without horizontal overflow.
- ✅ #b10 Event detail has resilient full/core requests plus explicit loading/error completion.

## Detail and navigation batch #1–#10 (2026-08-09)

- ✅ #1 The leading Home artwork has a fixed, width-bounded compact height and no longer overflows; its oversized glass text panel was replaced by a compact direct-on-gradient title treatment.
- ✅ #2 Event and entity details support an explicit left-edge swipe-back gesture in addition to native interactive pop.
- ✅ #3 Similar persons and ensembles use a horizontal carousel with circular portraits.
- ✅ #4 Venue previews and details lead with venue artwork; upcoming events are chronologically grouped and long lists collapse after six entries.
- ✅ #5 Calendar-day concerts use one ordered native list with compact artwork, time, venue and navigation affordance.
- ✅ #6 Ensemble type/category labels such as `Sonstiges` or `Chor` are no longer shown.
- ✅ #7 Venue, person, ensemble and work event rows navigate to their event details.
- ✅ #8 Horizontal Home event cards use a smaller 196-point layout with 110-point artwork.
- ✅ #9 Work lists and details contain no image slots; titles are normalized and composer, catalog, key, year, duration, instrumentation and movements are shown when present.
- ✅ #10 Event detail keeps an always-accessible ticket action at the bottom and falls back to the official event page when no dedicated ticket URL is available.

Verification: iPhone 17 Pro (iOS 26.5) and iPad mini (iOS 18.6) simulator builds succeeded, live Supabase work queries returned HTTP 200, and all 4 automated tests passed.

## Tappable genre chips and Editorial event editor cleanup (2026-08-14)

- ✅ Event detail genre chips are tappable — mirrors the Flutter app's
  `eventFiltersProvider` behavior. Tapping a genre (not the free-text
  `category` label, which stays plain) switches to the Search tab and shows a
  genre-filtered event list with a "Filter entfernen" action. New pieces:
  `GenreFilterRouter` (shared `@EnvironmentObject`, `Core/GenreFilterRouter.swift`),
  `EventRepository.events(genreID:limit:)` (live + preview), and a genre
  filter section in `SearchView`. Tappable chips are visually distinguished
  with an accent tint; the static category chip stays neutral.
- ✅ `EditorialEventEditorView` (Redaktion → Veranstaltung bearbeiten) no
  longer uses a custom `ScrollView`/`VStack`/card layout with a hand-rolled
  section-picker tab bar — it is now a single `Form` with native `Section`s
  (Basisdaten, Weitere Angaben, Mitwirkende, Programm, KI-Recherche, Löschen),
  matching the existing `EditorialEntityEditorView` pattern. Removed the
  now-unused `EditorialEventEditorSection`/`EditorialEventSectionPicker` and
  the custom `EditorialTextField` wrapper; the toolbar `Menu` for the single
  delete action became a plain destructive Form section button.

Verification: iPhone 17 Pro (iOS 26.5) simulator build and full test suite
succeeded; live-tested tapping a genre chip on a real event ("Orgel") →
correct tab switch and filtered event list, and "Filter entfernen" restoring
the normal Search view. Editorial portal change verified by successful build
+ tests only (Redaktionsmodus requires sign-in, not exercised live this
session) — same Form pattern is already proven live in
`EditorialEntityEditorView`.

## Entity links, ticket truth and search thumbnails #1–#7 (2026-08-09)

- ✅ #1 Program composers and all participant rows navigate to person/ensemble details. Participant rows prefer real circular `photo_url` images, then licensed gallery images, and use initials only when no real image exists.
- ✅ #2 The UI no longer invents `Preis auf Anfrage`; it displays only explicit free/minimum/maximum prices and verified ticket status fields.
- ✅ #3 Performance language is only rendered for opera/operetta-classified events.
- ✅ #4 The full venue card in event detail is a navigation link and accepts either slug or UUID routes.
- ✅ #5 Typed search results use event/venue thumbnails and circular person/ensemble thumbnails, including licensed gallery fallbacks.
- 🟡 #6 Live audit: 252 of 386 upcoming events have structured works; 134 do not. All 134 were already marked `references_checked_at`, 121 have an official URL, and 8 can inherit a sibling program. Migration `20261007000003_requeue_missing_event_programs.sql` safely requeues the 121 source-backed gaps but has not been deployed.
- ✅ #7 The duplicate leading content margin was removed from the similar-events rail.

Verification: live nested detail query returned HTTP 200 with venue, work and participant routes; generic simulator build succeeded; tests exited successfully; iPhone 17 Pro visual check confirmed the hidden unknown price, persistent ticket action, honest program fallback and linked venue card.

## Round avatar crop, person role labels, round person header (2026-08-09)

- ✅ #1 Person/ensemble circular avatars (directory list, search results, similar-entities rail) apply the editorial focal-point crop from the new `persons`/`ensembles.avatar_crop_x/y/width/height` columns (`20261007000005_person_name_parts_and_avatar_crop.sql`, mirrors the Flutter/admin feature) via the new `CroppedAsyncImage` component. Falls back to a plain centered fill when no crop is set — unchanged prior behavior.
- ✅ #2 Fixed raw lowercase role values (`dirigent`, `solist`, …) leaking into the UI — directory subtitles and a person's own event-participation rows now use the new `personRoleLabel` helper (mirrors `app/lib/core/constants/role_labels.dart`), matching the Flutter/admin display strings (`Dirigent:in`, `Solist:in`, …).
- ✅ #3 The person detail header photo is now circular (was a 120×150 rounded rectangle, shared with ensembles). Ensembles/works keep the previous rectangular header.

Verification: `xcodebuild build`/`xcodebuild test` succeeded (4/4 tests passing) after regenerating the project; visually confirmed on iPhone 16 Pro (iOS 18.6, material fallback) and iPhone 17 Pro (iOS 26.5, native `.glassEffect` Liquid Glass — confirmed via the floating glass tab bar) that the round header, cropped avatars and capitalized role labels render correctly under both. iPad not yet re-verified for this batch.

## Home, directories, collections and Admin batch (2026-08-09)

- ✅ Person dates use German `dd.MM.yyyy` formatting.
- ✅ Person, ensemble, venue and event artwork opens a zoomable full-screen viewer; ensemble and venue headers remain width-bounded for every source aspect ratio.
- ✅ Person, ensemble, venue and work directories are grouped and expose a right-side A–Z/# scrub index matching the iOS Contacts interaction.
- ✅ Home now contains personalized recommendations plus today, seven-day, weekend, popular, discovery, opera, orchestral, chamber, choral, free-entry and upcoming modules.
- ✅ Editorial collection details use an aspect-safe hero and compact full-width linked event rows instead of the former sparse two-column layout.
- ✅ Signed-in users can create, rename and delete named concert lists, search the complete upcoming program and add/remove arbitrary events. Data uses the existing RLS-protected `favorite_lists` and `favorite_list_items` tables.
- ✅ Admin event and group editing supports creating missing persons/ensembles and free event-specific role labels without changing entity master categories.
- ✅ Admin single-event editing can parse pasted cast text with AI, review the detected name/type/role, match existing entities and create selected missing entities.
- ✅ Admin person, ensemble, venue and event details have a read-only AI inconsistency audit for possible duplicates, shortened/unusual names, spelling variants, incomplete structured names, contradictory fields and implausible values. Possible duplicate records link directly to their edit page; the audit never mutates data.

Deployment/verification: iOS simulator build and all 7 tests passed; the current Home build was visually verified on the iOS 18.6 simulator. Admin production build and all 15 Vitest tests passed. Vercel production deployment `dpl_2qJz4noBwGUGvQi8qhsghRJXbaj5` is `READY` at `https://ko-kal-x-claude.vercel.app`. Supabase migrations `20261007000006` and `20261007000007` are applied; `parse-event-participants` and the read-only `audit-entity` function are `ACTIVE` with JWT verification enabled.

## Editorial delete (2026-08-14)

- ✅ Admin can delete venues, ensembles, persons and events from the native Editorial portal (`EditorialEntityEditorView`/`EditorialEventEditorView`), gated behind a `.confirmationDialog` with a destructive confirm button — same `is_admin_or_editor()` access check as the rest of the Editorial tab.
- ✅ Deletion runs through new Postgres RPCs (`delete_venue`, `delete_ensemble`, `delete_person`, `delete_event`, see `20261013000012`/`20261013000013_editorial_delete_rpcs*.sql`) that replicate the web admin's cascade-detach steps (`admin/src/app/(dashboard)/{venues,ensembles,persons}/actions.ts`) server-side — the native client makes a single `rpc()` call instead of re-implementing the multi-step detach order in Swift, where a missed step could leave orphaned foreign keys. `delete_event` also cleans up a now-empty event group (`programs` row), matching the admin-side fix for the "0 Termine" group bug.
- ⬜ Works are intentionally NOT deletable from native (or web admin's per-entity delete) — the existing works-duplicate-merge flow is the supported way to remove one.
- ✅ Full field-parity editing is done: `EditorialEntityEditorView` gained an "Weitere Angaben" section per kind (venue address/geo/capacity via the existing `update_venue` RPC, person first/middle/last name + roles + nationality + birth/death dates + ensemble link + verification, ensemble type/founded_year/member_count/home venue/parent ensemble) and `EditorialEventEditorView` gained a "Weitere Angaben" card (description, duration, intermission, organizer, genres, pricing, ticket info, status) saved via new `updatePersonDetails`/`updateEnsembleDetails`/`updateEventDetails`/`updateVenue` repository functions. Avatar crop (`avatar_crop_x/y/width/height`) is intentionally still out of scope — it needs a dedicated native crop tool matching the admin's `CropTool`, tracked as follow-up. Create flows were not extended (parity request was scoped to editing).

Verification: `xcodebuild build` and the full `xcodebuild test` suite (including 4 new field-parity `HTTPClient`-mocked tests plus the 3 existing delete tests) succeeded. Visually confirmed the app launches and renders live production data on iPhone 17 Pro after the change; the new form fields themselves were not clicked through live (no test editor account/credentials available in this environment to reach the signed-in-only Editorial tab).

## Onboarding/auth redesign (2026-08-19, 🟡 unverified)

Password-based signup replaces email-OTP as the login method; OTP is kept
internally only for signup email confirmation and password reset. Built in
the cloud sandbox session that also did the backend migration — **no
Xcode/Swift toolchain was available there**, so only manual brace/paren
balance checks and cross-reference greps were done. Needs
`ruby Scripts/generate_project.rb` (new files) + a real `xcodebuild build`
and a hands-on walkthrough before any row below can move to ✅.

- 🟡 `OnboardingView` rewritten as a `NavigationStack`-based step
  coordinator: Willkommen (Anmelden/Account erstellen/Gast) → Account
  erstellen (Passwort, Live-Anforderungscheck, AGB/Datenschutz) → E-Mail
  bestätigen → Persönliche Daten (Name/Geburtstag/Profilbild/Telefon/
  Adresse) → Interessen (reuses `InterestsView`) → Standort (new
  `CLLocationManager` wrapper, `update_home_location` RPC, München-only
  manual fallback via `regions`) → Benachrichtigungen (pre-permission
  explainer, then reuses `NotificationSettingsView`) → Zusammenfassung.
- 🟡 `PasswordLoginView`/`ForgotPasswordView` replace the old
  `EmailCodeLoginView` as the Profile-tab and returning-login surface.
- 🟡 Face ID: new `BiometricAuth` wrapper + a toggle in Profile's account
  section. Not yet wired as an app-launch lock screen — currently only
  exposed as a settings toggle with no enforcement point.
- 🟡 `RootTabView` now observes `AuthStore` as `@ObservedObject` (it
  wasn't before — needed for the onboarding re-show `.onChange` to fire
  at all) and re-shows onboarding for an authenticated user whose
  `profiles.onboarding_completed` is still false server-side, not only
  on the local per-install flag.
- ⬜ Sign in with Apple's native `ASAuthorizationAppleID` polish and true
  WebAuthn passkeys are explicitly deferred (blocked on an Apple
  Developer Program membership / a self-built WebAuthn backend
  respectively) — "Passkey" here means iOS's standard iCloud Keychain
  password autofill (`textContentType`), nothing more.
- ⬜ Not yet done: light/dark, iPad, Dynamic Type/VoiceOver, and
  automated-test passes per the parity checklist below — none of that
  was possible without a toolchain.

## Home: Favoriten & gefolgte Personen/Ensembles/Orte als eigene Kategorien (2026-08-20, 🟡 unverified)

Nutzerwunsch: "Favoriten" sowie "Gefolgte Personen", "Gefolgte Ensembles" und
"Gefolgte Orte" sollen jeweils eine eigene Homepage-Kategorie sein (statt
einer einzigen kombinierten "Gefolgte Künstler & Orte"-Reihe), sowohl auf dem
Home-Screen als auch in "Homepage anordnen". Built in the cloud sandbox
session — no Xcode/Swift toolchain available there, only manual
cross-reference checks against the existing enum/switch pattern.

- 🟡 `HomeRecommendationCategory` (`Features/Home/HomeView.swift`) replaces
  the combined `.followed` case with four new cases: `.favorites`,
  `.followedPersons`, `.followedEnsembles`, `.followedVenues` — each with its
  own title/SF-Symbol, so they show up in the existing "Homepage anordnen"
  reorder screen (`HomeCategoryOrderView` in `ProfileView.swift`) automatically
  via `HomeCategoryPreferences.order(for:)`'s existing "append any new/missing
  case" merge logic — no changes needed there.
- 🟡 `.favorites` renders as an `EventRail` filtered against the already-
  injected `FavoriteStore.ids` (now also `@EnvironmentObject` on `HomeView`,
  previously only used by `EventCard`/`EventDetailView`).
- 🟡 `.followedPersons`/`.followedEnsembles`/`.followedVenues` reuse a
  generalized `followedSections(from:kind:)` (previously hardcoded to mix all
  three kinds into one rail) — one `EventRail` per followed entity of that
  kind with upcoming matching events, via the existing `FollowStore`.
- 🟡 Follow-up fix ("auch gefolgte ensembles anzeigen"): the event-based
  `followedSections` approach only ever surfaced a followed ensemble if it
  already had an upcoming event in the top-100 loaded feed — a followed
  ensemble with no current event was invisible. `.followedEnsembles` now
  additionally fetches the full ensemble directory once
  (`contentRepository.directory(kind: .ensemble)`) and renders a new
  self-hiding `EntityRail` card row (circular photo + name, links via the
  existing `EntityRoute`/`EntityDetailView`) for every followed ensemble not
  already covered by an event-based rail, so no followed ensemble is ever
  invisible on Home regardless of whether it has a scheduled event.
- ⬜ Not yet done: Xcode build/tests, visual verification (light/dark, iPad,
  Dynamic Type), and Flutter-side parity (`app/lib/features/home/`) — the
  user asked for native first.

## In-app Impressum (2026-08-20, 🟡 unverified)

Nutzeranfrage: "füge das urheberrecht noch in die app ein", mit dem
aktuellen, vollständigen Impressum-Text im Prompt (Anbieterkennzeichnung §5
DDG, Kontakt, Verantwortlich für den Inhalt, Haftung für Inhalte, Haftung
für externe Links, Urheberrecht). Bisher verlinkte die App nur extern auf
`https://klangradar.app/impressum` — der Urheberrecht-Abschnitt (und der
Rest des Texts) existierte nirgends *in* der App selbst.

- 🟡 Neue `Features/Profile/ImpressumView.swift` — Liste mit einem
  `Section` je Abschnitt, exakter Text wie vom Nutzer vorgegeben.
- 🟡 `ProfileView.swift` → "Über Klangradar": "Impressum" ist jetzt ein
  `NavigationLink` auf `ImpressumView` statt eines externen `Link`
  (Datenschutz bleibt bewusst extern verlinkt, dafür lag kein Text vor).
- 🟡 `SignUpStepView.swift` (Onboarding-AGB-Zustimmung): "Impressum (AGB)"
  öffnet dieselbe `ImpressumView` jetzt als Sheet statt extern zu
  verlinken, damit der Text auch dort ohne Browser-Wechsel einsehbar ist.
- 🟡 `ruby Scripts/generate_project.rb` wurde in dieser Sandbox-Session
  ausgeführt (xcodeproj-Gem nachinstalliert) — die neue Datei ist im
  Xcode-Projekt referenziert; die große pbxproj/xcscheme-Diff-Größe ist
  reines UUID-Rebuild-Rauschen des Generators (baut die Projektdatei bei
  jedem Lauf komplett neu auf), keine inhaltliche Änderung.
- ⬜ Kein Xcode/Swift-Toolchain hier verfügbar — Build, Light/Dark,
  Dynamic Type und die visuelle Prüfung stehen noch aus.

## Definition of feature parity

A row can be marked complete only when it:

1. matches the current Flutter behavior and backend contract,
2. has loading, empty, error and offline behavior,
3. works in light and dark appearance,
4. supports iPhone and iPad layouts,
5. supports Dynamic Type and VoiceOver,
6. has automated tests and has been run in both simulator classes.
