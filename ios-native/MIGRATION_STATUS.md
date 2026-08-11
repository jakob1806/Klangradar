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

## Definition of feature parity

A row can be marked complete only when it:

1. matches the current Flutter behavior and backend contract,
2. has loading, empty, error and offline behavior,
3. works in light and dark appearance,
4. supports iPhone and iPad layouts,
5. supports Dynamic Type and VoiceOver,
6. has automated tests and has been run in both simulator classes.
