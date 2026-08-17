import 'dart:async';

import 'package:add_2_calendar/add_2_calendar.dart' as add2cal;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/events/event_filters.dart';
import '../../../core/events/filtered_events_providers.dart';
import '../../../core/gallery/entity_gallery_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/detail_hero_background.dart';
import '../../../core/widgets/entity_photo_gallery.dart';
import '../../../core/widgets/event_section.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/utils/share_position.dart';
import '../../../core/widgets/report_content_sheet.dart';
import '../../../core/widgets/source_hint.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/application/home_providers.dart';

/// Öffnet die native "Neuer Termin"-Vorlage des Betriebssystems (auf iOS:
/// EKEventEditViewController — dieselbe Ansicht wie beim direkten Anlegen
/// eines Termins in der Apple-Kalender-App), vorausgefüllt mit den
/// Event-Daten. Die Nutzerin wählt Kalender/bearbeitet/speichert selbst —
/// Nutzeranfrage: "der Button 'kalender' soll erst einmal ein pop up
/// öffnen, wo man entscheiden kann, in welchen kalender man es
/// importiert... so eine vorlage von apple, die aussieht, als würde man
/// gerade ein ereignis im apple kalender erstellen". Ersetzt die bisherige
/// Variante (device_calendar, Berechtigungsabfrage + eigenes BottomSheet +
/// stilles Schreiben ohne native UI).
Future<void> _addEventToDeviceCalendar({
  required BuildContext context,
  required String title,
  required DateTime start,
  String? description,
  int? durationMinutes,
  String? location,
  String? url,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  final added = await add2cal.Add2Calendar.addEvent2Cal(
    add2cal.Event(
      title: title,
      description: description,
      location: location,
      startDate: start,
      endDate: start.add(Duration(minutes: durationMinutes ?? 120)),
      iosParams: add2cal.IOSParams(url: url),
    ),
  );
  if (!context.mounted || added) return;
  messenger.showSnackBar(SnackBar(content: Text(l10n.eventCalendarAddFailed)));
}

final _eventProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  slug,
) async {
  final event = await Supabase.instance.client
      .from('events')
      .select('''
        id, slug, title, subtitle, description_de,
        start_datetime, duration_minutes, has_intermission, venue_detail,
        ticket_url, price_min, price_max, price_currency, is_free,
        remaining_tickets_status, doors_info, age_restriction,
        discount_info, presale_fee_info, target_audience, performance_language,
        website_url, accessibility, status, image_urls, program_id,
        attribution_notice, attribution_license_url, last_verified_at,
        venues(id, slug, name, address_street, address_zip, address_city, photo_url, description_de),
        organizers(name),
        event_genres(genres(id, slug, label_de)),
        event_works(position, after_intermission, works(id, title, catalog_number, key_signature, instrumentation, movements, composer:persons(slug, full_name))),
        event_participants(role, persons(id, slug, full_name, member_of:ensembles!member_of_ensemble_id(slug, name)), ensembles(id, slug, name, parent_ensemble_id))
      ''')
      .eq('slug', slug)
      .neq('status', 'draft')
      .maybeSingle();

  // ensembles.parent_ensemble_id ist ein Self-Join (siehe Kommentar in
  // ensemble_detail_screen.dart) — PostgREST-Embedding liefert dafür
  // zuverlässig nur die Rückwärts-Richtung, deshalb hier für alle
  // Mitwirkenden-Ensembles manuell in einem zweiten Schritt aufgelöst.
  if (event != null) {
    final participantEnsembles = (event['event_participants'] as List)
        .map((p) => p['ensembles'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .toList();
    final parentIds = participantEnsembles
        .map((e) => e['parent_ensemble_id'])
        .whereType<String>()
        .toSet();
    if (parentIds.isNotEmpty) {
      final parents = await Supabase.instance.client
          .from('ensembles')
          .select('id, slug, name')
          .inFilter('id', parentIds.toList());
      final parentById = {for (final p in parents) p['id'] as String: p};
      for (final e in participantEnsembles) {
        final parentId = e['parent_ensemble_id'] as String?;
        if (parentId != null && parentById.containsKey(parentId)) {
          e['parent'] = parentById[parentId];
        }
      }
    }
  }

  // Speist recommended_events()'s Venue-"besucht"-Signal — siehe
  // docs/06-mvp-plan.md. Fire-and-forget, blockiert nicht das Rendern.
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (event != null && userId != null) {
    unawaited(
      Supabase.instance.client.from('event_views').insert({
        'user_id': userId,
        'event_id': event['id'],
      }),
    );
  }
  if (event == null) return null;

  // Quellenbelege für Werk-Felder (Instrumentierung/Satzfolge, siehe
  // enrich-work-profile) — je Werk-ID gruppiert, Phase 6: "dezente, aber
  // nachvollziehbare Quellenhinweise".
  final workIds = (event['event_works'] as List)
      .map((ew) => ew['works']?['id'] as String?)
      .whereType<String>()
      .toList();
  var workSources = <String, Map<String, FieldSource>>{};
  if (workIds.isNotEmpty) {
    final provenance = await Supabase.instance.client
        .from('field_provenance')
        .select(
          'entity_id, field_name, source_name, source_url, retrieved_at, confidence',
        )
        .eq('entity_type', 'work')
        .inFilter('entity_id', workIds);
    workSources = <String, Map<String, FieldSource>>{};
    for (final row in provenance as List) {
      final id = row['entity_id'] as String;
      (workSources[id] ??= {})[row['field_name'] as String] =
          FieldSource.fromRow(row as Map<String, dynamic>);
    }
  }

  // Änderungstransparenz (Phase A.2, docs/09-feature-expansion-plan.md) —
  // der events_log_changes-Trigger (Migration 20261002000011) protokolliert
  // Beginn-/Orts-/Status-Änderungen unabhängig davon, welcher Pfad sie
  // geschrieben hat (Ingestion, Admin-Dashboard, Enrichment-Functions).
  final changes = await Supabase.instance.client
      .from('event_changes')
      .select('field_name, old_value, new_value, changed_at')
      .eq('event_id', event['id'])
      .order('changed_at', ascending: false)
      .limit(5);

  return {...event, '_workSources': workSources, '_changes': changes};
});

typedef _SimilarEventsKey = ({
  String eventId,
  String? genreId,
  String? venueId,
});

final _similarEventsProvider =
    FutureProvider.family<List<HomeEventItem>, _SimilarEventsKey>((
      ref,
      key,
    ) async {
      if (key.genreId == null && key.venueId == null) return [];

      final rows = await Supabase.instance.client.rpc(
        'similar_events',
        params: {
          'p_event_id': key.eventId,
          'p_genre_id': key.genreId,
          'p_venue_id': key.venueId,
        },
      );
      return (rows as List)
          .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
          .toList();
    });

/// Andere Termine desselben Konzerts (Nutzeranfrage: "falls ein konzert
/// mehrere male aufgeführt wird, soll es... eine kategorie geben 'Weitere
/// Termine'"). programId ist events.program_id — dieselbe Gruppierung, die
/// die Admin-Event-Gruppen-Verwaltung schon für das gemeinsame
/// Programm/Mitwirkende nutzt (siehe admin event-groups).
final _otherDatesProvider =
    FutureProvider.family<
      List<Map<String, dynamic>>,
      ({String programId, String currentEventId})
    >((ref, key) async {
      final rows = await Supabase.instance.client
          .from('events')
          .select('slug, start_datetime')
          .eq('program_id', key.programId)
          .neq('id', key.currentEventId)
          .neq('status', 'draft')
          .order('start_datetime', ascending: true);
      return (rows as List).cast<Map<String, dynamic>>();
    });

String _formatVerifiedDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

Map<String, String?> _statusLabels(AppLocalizations l10n) => {
  'scheduled': null,
  'sold_out': l10n.eventStatusSoldOut,
  'cancelled': l10n.eventStatusCancelled,
  'postponed': l10n.eventStatusPostponed,
};

Map<String, String> _roleLabels(AppLocalizations l10n) => {
  'komponist': l10n.roleComposer,
  'dirigent': l10n.roleConductor,
  'solist': l10n.roleSoloist,
  'chorleiter': l10n.roleChoirmaster,
  'moderator': l10n.roleModerator,
};

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_eventProvider(slug));
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.errorLoadingGeneric(e.toString()))),
        data: (event) {
          if (event == null) {
            return Center(
              child: Text(
                l10n.eventNotFound,
                style: TextStyle(color: colors.textSecondary),
              ),
            );
          }

          final genreSlugs = (event['event_genres'] as List)
              .map((g) => g['genres']?['slug'] as String?)
              .whereType<String>()
              .toList();
          final primaryGenre = EventGenre.fromSlug(
            genreSlugs.isEmpty ? null : genreSlugs.first,
          );
          final genrePairs = (event['event_genres'] as List)
              .map((g) => g['genres'] as Map<String, dynamic>?)
              .whereType<Map<String, dynamic>>()
              .where((g) => g['id'] != null && g['label_de'] != null)
              .map(
                (g) => (id: g['id'] as String, label: g['label_de'] as String),
              )
              .toList();
          final primaryGenreId = genrePairs.firstOrNull?.id;

          final start = MunichTime.tryParse(event['start_datetime']);
          final venue = event['venues'] as Map<String, dynamic>?;
          final similarEvents =
              ref
                  .watch(
                    _similarEventsProvider((
                      eventId: event['id'] as String,
                      genreId: primaryGenreId,
                      venueId: venue?['id'] as String?,
                    )),
                  )
                  .valueOrNull ??
              const [];
          final works = (event['event_works'] as List)
            ..sort(
              (a, b) => (a['position'] as int).compareTo(b['position'] as int),
            );
          final workSources =
              event['_workSources'] as Map<String, Map<String, FieldSource>>;
          final participants = event['event_participants'] as List;
          final accessibility =
              (event['accessibility'] as Map<String, dynamic>?) ?? {};
          final statusBadge = _statusLabels(l10n)[event['status']];
          final imageUrls = event['image_urls'] as List?;
          final eventPhotoUrl = (imageUrls != null && imageUrls.isNotEmpty)
              ? imageUrls.first as String?
              : null;
          final photoUrl = eventPhotoUrl ?? venue?['photo_url'] as String?;
          final gallery = ref.watch(
            entityGalleryProvider((
              originType: 'event',
              originId: event['id'] as String,
            )),
          );
          // Nutzerwunsch: wenn eine Veranstaltung KEIN eigenes Bild hat,
          // aber nur EIN(E) Mitwirkende(r) (Person/Ensemble, Komponisten
          // zählen nicht als "beteiligt vor Ort") oder — falls das auch
          // nicht eindeutig ist — nur EIN Werk im Programm steht, wird
          // deren dauerhaft gepflegtes Bild/Slideshow gezeigt statt des
          // generischen Genre-Platzhalters. Wichtig: NUR bei genau einem
          // eindeutigen Treffer — bei mehreren Mitwirkenden/Werken wäre es
          // irreführend, das Bild von nur einem/einer davon zu zeigen.
          final performerIds = <String>{};
          for (final p in participants) {
            if (p['role'] == 'komponist') continue;
            final personId = p['persons']?['id'] as String?;
            final ensembleId = p['ensembles']?['id'] as String?;
            if (personId != null) performerIds.add('person:$personId');
            if (ensembleId != null) performerIds.add('ensemble:$ensembleId');
          }
          final workIds = works
              .map((w) => w['works']?['id'] as String?)
              .whereType<String>()
              .toSet();
          ({String originType, String originId})? fallbackGalleryKey;
          if (performerIds.length == 1) {
            final parts = performerIds.first.split(':');
            fallbackGalleryKey = (originType: parts[0], originId: parts[1]);
          } else if (workIds.length == 1) {
            fallbackGalleryKey = (originType: 'work', originId: workIds.first);
          } else if (venue?['id'] != null) {
            // Letzte Stufe: hochauflösende Venue-Galerie. Der Provider
            // schließt low_resolution explizit aus; photo_url bleibt unten
            // nur als Altbestands-Fallback, falls keine Galerie existiert.
            fallbackGalleryKey = (
              originType: 'venue',
              originId: venue!['id'] as String,
            );
          }
          final fallbackGallery = fallbackGalleryKey != null
              ? ref.watch(entityGalleryProvider(fallbackGalleryKey))
              : null;

          return _DwellTimeTracker(
            eventId: event['id'] as String,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  backgroundColor: colors.backgroundPrimary,
                  iconTheme: const IconThemeData(color: Colors.white),
                  actions: [
                    FavoriteButton(
                      eventId: event['id'],
                      activeColor: colors.accentPrimary,
                      inactiveColor: Colors.white,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: l10n.eventAddToCalendarTooltip,
                      onPressed: start == null
                          ? null
                          : () => _addEventToDeviceCalendar(
                              context: context,
                              title: event['title'] ?? '',
                              description: event['description_de'],
                              start: start,
                              durationMinutes: event['duration_minutes'],
                              location: venue != null
                                  ? '${venue['name']}${event['venue_detail'] != null ? ' · ${event['venue_detail']}' : ''}, ${venue['address_street']}, ${venue['address_zip']} ${venue['address_city']}'
                                  : null,
                              url: event['website_url'] ?? event['ticket_url'],
                            ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.ios_share_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: l10n.eventShareTooltip,
                      onPressed: () => Share.share(
                        '${event['title']}${venue != null ? ' · ${venue['name']}' : ''}'
                        '${event['website_url'] != null ? '\n${event['website_url']}' : ''}',
                        sharePositionOrigin: sharePositionOriginFor(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        Builder(
                          builder: (context) {
                            final ownImages = gallery.valueOrNull ?? const [];
                            if (ownImages.isNotEmpty) {
                              return EntityPhotoGallery(
                                images: ownImages,
                                fallbackGenre: primaryGenre,
                                showGradient: false,
                              );
                            }
                            final fallbackImages =
                                fallbackGallery?.valueOrNull ?? const [];
                            if (fallbackImages.isNotEmpty) {
                              return EntityPhotoGallery(
                                images: fallbackImages,
                                fallbackGenre: primaryGenre,
                                showGradient: false,
                              );
                            }
                            return DetailHeroBackground(
                              photoUrl: photoUrl,
                              fallbackGenre: primaryGenre,
                              showGradient: false,
                            );
                          },
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x59000000),
                                Colors.transparent,
                                Color(0xBF000000),
                              ],
                              stops: [0.0, 0.35, 1.0],
                            ),
                          ),
                        ),
                        if (statusBadge != null)
                          Positioned(
                            left: 16,
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.error,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusBadge,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPaddingMobile,
                    AppSpacing.lg,
                    AppSpacing.screenPaddingMobile,
                    0,
                  ),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        event['title'] ?? '',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      if (event['subtitle'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          event['subtitle'],
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          // Antippbar (Nutzerwunsch: "schön wäre es, dass man
                          // sie antippen kann und dann alle Veranstaltungen mit
                          // dieser Kategorie sehen kann") — setzt denselben
                          // eventFiltersProvider, den auch die Filter-Sheet/
                          // Karten-Chips nutzen, und wechselt zum Suche-Tab,
                          // der bei aktivem Filter automatisch die gefilterte
                          // Liste statt der Sucheingabe zeigt.
                          for (final genre in genrePairs)
                            ActionChip(
                              label: Text(
                                genre.label,
                                style: const TextStyle(fontSize: 11),
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                ref.read(eventFiltersProvider.notifier).state =
                                    EventFilters(genreIds: {genre.id});
                                context.go('/search');
                              },
                            ),
                          if (event['is_free'] == true)
                            Chip(
                              label: Text(
                                l10n.eventFree,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: colors.success.withValues(
                                alpha: 0.15,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        [
                          if (start != null)
                            l10n.eventDateTimeLine(
                              _weekday(l10n, start),
                              '${start.day}.${start.month}.${start.year}',
                              _time(start),
                            ),
                          if (event['duration_minutes'] != null)
                            '${l10n.eventMinutes(event['duration_minutes'])}${event['has_intermission'] == true ? l10n.eventIncludingIntermission : ''}',
                        ].join(' — '),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      if (venue != null) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => context.push('/venue/${venue['slug']}'),
                          child: Text(
                            '${venue['name']}${event['venue_detail'] != null ? ' · ${event['venue_detail']}' : ''} — ${venue['address_street']}, ${venue['address_zip']} ${venue['address_city']}',
                            style: TextStyle(
                              color: colors.accentPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      _ChangesNotice(
                        changes: (event['_changes'] as List?) ?? const [],
                        colors: colors,
                      ),
                      _TicketInfoSection(event: event, colors: colors),
                      // description_de kommt bei vielen Quellen als reine
                      // Komma-Aufzählung der Werke/Komponisten (die
                      // Quell-Website selbst schreibt sie so, keine
                      // KI-Erfindung) — sobald ein geparstes Programm
                      // existiert, würde die Ansicht dieselbe Information
                      // zweimal zeigen (einmal als Fließtext, einmal als
                      // "Programm"-Liste direkt darunter). Nur ohne
                      // Programm zeigen.
                      if (event['description_de'] != null && works.isEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          event['description_de'],
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (event['program_id'] != null)
                        _OtherDatesSection(
                          programId: event['program_id'] as String,
                          currentEventId: event['id'] as String,
                          colors: colors,
                        ),
                      if (works.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          l10n.eventProgramTitle,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DetailCard(
                          children: [
                            for (final w in works)
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: _ProgramRow(
                                  work: w,
                                  colors: colors,
                                  sources:
                                      workSources[w['works']?['id']] ??
                                      const {},
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (participants.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          l10n.eventParticipantsTitle,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DetailCard(
                          children: [
                            for (final p in participants)
                              _ParticipantRow(participant: p, colors: colors),
                          ],
                        ),
                      ],
                      if (accessibility.values.any((v) => v == true)) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          l10n.eventAccessibilityTitle,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (accessibility['wheelchair'] == true)
                              Chip(
                                label: Text(l10n.eventAccessibilityWheelchair),
                              ),
                            if (accessibility['hearing_loop'] == true)
                              Chip(
                                label: Text(l10n.eventAccessibilityHearingLoop),
                              ),
                            if (accessibility['sign_language'] == true)
                              Chip(
                                label: Text(
                                  l10n.eventAccessibilitySignLanguage,
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (event['attribution_notice'] != null ||
                          event['last_verified_at'] != null) ...[
                        const SizedBox(height: AppSpacing.xl),
                        if (event['attribution_notice'] != null)
                          _AttributionNotice(
                            notice: event['attribution_notice'] as String,
                            licenseUrl:
                                event['attribution_license_url'] as String?,
                            colors: colors,
                          ),
                        if (event['last_verified_at'] != null) ...[
                          if (event['attribution_notice'] != null)
                            const SizedBox(height: 2),
                          Text(
                            l10n.eventLastVerified(
                              _formatVerifiedDate(
                                DateTime.parse(
                                  event['last_verified_at'] as String,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      ReportContentLink(
                        entityType: 'event',
                        entityId: event['id'] as String,
                      ),
                    ],
                  ),
                ),
                if (venue != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPaddingMobile,
                      AppSpacing.xl,
                      AppSpacing.screenPaddingMobile,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _VenueSection(venue: venue, colors: colors),
                    ),
                  ),
                if (similarEvents.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    sliver: SliverToBoxAdapter(
                      child: EventSection(
                        title: l10n.eventSimilarEvents,
                        events: similarEvents,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xl),
                ),
              ],
            ),
          );
        },
      ),
      // bottomNavigationBar statt eines Positioned-Overlays mit von Hand
      // ausgemessenem Platzhalter im Scroll-Inhalt (frühere Version, siehe
      // Git-Historie) — Scaffold reserviert dafür automatisch exakt die
      // tatsächliche Höhe der Leiste, ganz gleich wie viele Zeilen sie
      // gerade zeigt (Preis allein, oder zusätzlich eine Ticket-Status-
      // Zeile). Ein von Hand geschätzter Fixwert lag zweimal daneben
      // (Button-Variante, dann die Status-Zeile) — das kann mit dieser
      // Konstruktion strukturell nicht mehr passieren.
      bottomNavigationBar: async.maybeWhen(
        data: (event) =>
            event == null ? null : _TicketBar(event: event, colors: colors),
        orElse: () => null,
      ),
    );
  }

  String _weekday(AppLocalizations l10n, DateTime d) => [
    l10n.weekdayMonShort,
    l10n.weekdayTueShort,
    l10n.weekdayWedShort,
    l10n.weekdayThuShort,
    l10n.weekdayFriShort,
    l10n.weekdaySatShort,
    l10n.weekdaySunShort,
  ][d.weekday - 1];
  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

List<String> _fullWeekdayNames(AppLocalizations l10n) => [
  l10n.weekdayMonday,
  l10n.weekdayTuesday,
  l10n.weekdayWednesday,
  l10n.weekdayThursday,
  l10n.weekdayFriday,
  l10n.weekdaySaturday,
  l10n.weekdaySunday,
];

List<String> _fullMonthNames(AppLocalizations l10n) => [
  l10n.monthJanuary,
  l10n.monthFebruary,
  l10n.monthMarch,
  l10n.monthApril,
  l10n.monthMay,
  l10n.monthJune,
  l10n.monthJuly,
  l10n.monthAugust,
  l10n.monthSeptember,
  l10n.monthOctober,
  l10n.monthNovember,
  l10n.monthDecember,
];

/// Verweildauer-Tracking (docs/08-home-feed-recommendation-algorithm.md,
/// Abschnitt 4.1/9) — misst, wie lange die Detailseite offen war, und
/// schreibt das bei dispose() in event_views.duration_seconds nach. Der
/// event_views-Insert selbst passiert weiter fire-and-forget in
/// _eventProvider (dort kennen wir nur den Startzeitpunkt); hier wird nur
/// die zuletzt offene, noch nicht abgeschlossene Zeile derselben Person für
/// dieses Event aktualisiert — kein neuer Nachschlag nach einer konkreten
/// Zeilen-ID nötig. Nur für eingeloggte Nutzer:innen, gleiche Einschränkung
/// wie der event_views-Insert.
class _DwellTimeTracker extends StatefulWidget {
  const _DwellTimeTracker({required this.eventId, required this.child});
  final String eventId;
  final Widget child;

  @override
  State<_DwellTimeTracker> createState() => _DwellTimeTrackerState();
}

class _DwellTimeTrackerState extends State<_DwellTimeTracker> {
  late final DateTime _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
  }

  @override
  void dispose() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final seconds = DateTime.now().difference(_openedAt).inSeconds;
      unawaited(
        Supabase.instance.client
            .from('event_views')
            .update({'duration_seconds': seconds})
            .eq('user_id', userId)
            .eq('event_id', widget.eventId)
            .isFilter('duration_seconds', null),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Weitere Termine": andere Aufführungen desselben Konzerts (gleiches
/// events.program_id), tappable zum jeweils anderen Event — Nutzeranfrage:
/// "falls ein konzert mehrere male aufgeführt wird, soll es vor der
/// kategorie 'Programm'... eine kategorie geben 'Weitere Termine'... das
/// format soll ungefähr so sein wie im screenshot" (umrandete Zeilen: fetter
/// Wochentag, Datum darunter, Uhrzeit rechtsbündig normal). Rendert nichts,
/// solange die Gruppe (noch) keine weiteren Termine hat — z.B. eine
/// Event-Gruppe mit bisher nur einem angelegten Termin.
class _OtherDatesSection extends ConsumerWidget {
  const _OtherDatesSection({
    required this.programId,
    required this.currentEventId,
    required this.colors,
  });

  final String programId;
  final String currentEventId;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      _otherDatesProvider((
        programId: programId,
        currentEventId: currentEventId,
      )),
    );
    final dates = async.valueOrNull ?? const [];
    if (dates.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.eventOtherDates,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in dates) ...[
            _OtherDateRow(row: row, colors: colors),
            if (row != dates.last) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _OtherDateRow extends StatelessWidget {
  const _OtherDateRow({required this.row, required this.colors});

  final Map<String, dynamic> row;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final start = MunichTime.tryParse(row['start_datetime'] as String?);
    final slug = row['slug'] as String?;
    if (start == null || slug == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;

    final weekday = _fullWeekdayNames(l10n)[start.weekday - 1];
    final date =
        '${start.day}. ${_fullMonthNames(l10n)[start.month - 1]} ${start.year}';
    final time = l10n.eventOtherDateTime(
      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
    );

    return Semantics(
      button: true,
      label: l10n.eventOtherDateSemanticsLabel(weekday, date, time),
      onTap: () => context.push('/event/$slug'),
      child: Material(
        color: colors.backgroundPrimary,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: InkWell(
          onTap: () => context.push('/event/$slug'),
          borderRadius: BorderRadius.circular(AppSpacing.md),
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                border: Border.all(color: colors.separator),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          weekday,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          date,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    time,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kurzinfo zum Veranstaltungsort (Foto, Name, Adresse, ggf. Kurzbeschreibung)
/// — auf Nutzerwunsch vor "Ähnliche Veranstaltungen" platziert, damit die
/// Location nicht nur als Adresszeile oben auf der Seite auftaucht.
class _VenueSection extends StatelessWidget {
  const _VenueSection({required this.venue, required this.colors});

  final Map<String, dynamic> venue;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final photoUrl = venue['photo_url'] as String?;
    final description = venue['description_de'] as String?;
    final cardRadius = BorderRadius.circular(AppRadius.cardImage);
    final address =
        '${venue['address_street']}, ${venue['address_zip']} ${venue['address_city']}';
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.eventVenueSectionTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          button: true,
          label: '${venue['name']}, $address',
          onTap: () => context.push('/venue/${venue['slug']}'),
          child: GestureDetector(
            onTap: () => context.push('/venue/${venue['slug']}'),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: cardRadius,
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: photoUrl != null
                          ? CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  GenreArtwork(
                                    genre: EventGenre.kirchenmusik,
                                    borderRadius: cardRadius,
                                  ),
                              placeholder: (context, url) => GenreArtwork(
                                genre: EventGenre.kirchenmusik,
                                borderRadius: cardRadius,
                              ),
                            )
                          : GenreArtwork(
                              genre: EventGenre.kirchenmusik,
                              borderRadius: cardRadius,
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          venue['name'] ?? '',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pflicht-Urheberrechtsvermerk für Quellen mit expliziter Lizenzauflage
/// (z.B. BayernCloud Tourismus: "der entsprechende Urheberrechtsvermerk der
/// Datensätze muss mit angegeben werden") — null für alle anderen Quellen,
/// zeigt sich also nur bei Events aus einer solchen Quelle.

class _AttributionNotice extends StatelessWidget {
  const _AttributionNotice({
    required this.notice,
    required this.licenseUrl,
    required this.colors,
  });

  final String notice;
  final String? licenseUrl;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Text(
      l10n.eventDataSource(notice),
      style: TextStyle(color: colors.textTertiary, fontSize: 11),
    );
    if (licenseUrl == null) return text;
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(licenseUrl!),
        mode: LaunchMode.externalApplication,
      ),
      child: text,
    );
  }
}

class _ProgramRow extends StatelessWidget {
  const _ProgramRow({
    required this.work,
    required this.colors,
    this.sources = const {},
  });
  final dynamic work;
  final AppColorsExtension colors;
  final Map<String, FieldSource> sources;

  @override
  Widget build(BuildContext context) {
    final w = work['works'] as Map<String, dynamic>?;
    if (w == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (work['after_intermission'] == true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l10n.eventIntermission,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.accentSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          // Untereinander statt nebeneinander (Nutzerfeedback: die
          // Zwei-Spalten-Anordnung wirkte bei längeren Komponisten-/
          // Werktiteln chaotisch/verrutscht) — folgt der aus gedruckten
          // Konzertprogrammen gewohnten Lesereihenfolge: Komponist zuerst,
          // Werktitel darunter, Zusatzinfos (Opus/Tonart) ganz unten klein.
          if (w['composer']?['full_name'] != null)
            Semantics(
              button: w['composer']?['slug'] != null,
              link: w['composer']?['slug'] != null,
              child: GestureDetector(
                onTap: w['composer']?['slug'] != null
                    ? () => context.push('/person/${w['composer']['slug']}')
                    : null,
                child: Text(
                  w['composer']['full_name'],
                  style: TextStyle(
                    color: w['composer']?['slug'] != null
                        ? colors.accentPrimary
                        : colors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Semantics(
            button: w['id'] != null,
            link: w['id'] != null,
            child: GestureDetector(
              // Zum Programm-Explorer (Phase C.1) — alle Aufführungen
              // dieses Werks, nicht nur diese eine.
              onTap: w['id'] != null
                  ? () => context.push('/work/${w['id']}')
                  : null,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  w['title'] ?? '',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          // Opus-/Werkverzeichnisnummer + Tonart nur, wenn recherchiert
          // (siehe enrich-event-references) — rein optional, keine leere
          // Zeile wenn nicht vorhanden.
          if ((w['catalog_number'] as String?)?.isNotEmpty == true ||
              (w['key_signature'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  w['catalog_number'],
                  w['key_signature'],
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(color: colors.textTertiary, fontSize: 11),
              ),
            ),
          // Instrumentierung (SATB/Bläserbesetzung/etc.) und die Satzfolge
          // (movements) werden bewusst NICHT angezeigt — auf Nutzerwunsch:
          // reines Rohbesetzungs-/Werkanalyse-Detail ohne Mehrwert für
          // Konzertbesucher, nicht das, was unter "Programm" erwartet wird.
          // Die Felder werden weiterhin von enrich-work-profile befüllt
          // (siehe dort), nur die Anzeige hier wurde entfernt.
        ],
      ),
    );
  }
}

/// Eine Zeile je Mitwirkendem — untereinander statt als eingekreiste Pills
/// (Nutzerwunsch: "Mitwirkende sollen immer untereinander stehen, zwar
/// anklickbar aber nicht so eingekreist"), gleiche Zeilensprache wie
/// _ProgramRow/_OtherDateRow: Name links, Rolle rechts, ganze Zeile tappbar.
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant, required this.colors});
  final dynamic participant;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final person = participant['persons'] as Map<String, dynamic>?;
    final ensemble = participant['ensembles'] as Map<String, dynamic>?;
    final name = person?['full_name'] ?? ensemble?['name'];
    if (name == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    // Ensembles haben in der Datenbank keine eigene role-Ausprägung (das
    // participant_role-Enum kennt nur komponist/dirigent/solist/
    // chorleiter/moderator, siehe 20260715000009_events.sql) — ohne diesen
    // Fallback stand bei Ensemble-Mitwirkenden gar keine Rollenbezeichnung
    // daneben, nur der bloße Name (Nutzermeldung: "'Ensemble' bei Münchner
    // Philharmoniker fehlt als Angabe").
    final role = ensemble != null
        ? l10n.roleEnsemble
        : _roleLabels(l10n)[participant['role']];
    final slug = person?['slug'] ?? ensemble?['slug'];
    // Nutzeranfrage: Verknüpfung zu einem übergeordneten Ensemble soll auch
    // hier in der Mitwirkenden-Liste erkennbar sein, nicht erst auf der
    // eigenen Detailseite der Person/des Ensembles.
    final parentEnsemble = person?['member_of'] ?? ensemble?['parent'];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: slug == null
            ? null
            : () => context.push(
                person != null ? '/person/$slug' : '/ensemble/$slug',
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: slug != null
                            ? colors.accentPrimary
                            : colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (role != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      role,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  if (slug != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ],
                ],
              ),
              if (parentEnsemble != null)
                Text(
                  'Teil von ${parentEnsemble['name']}',
                  style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label + Farbe für remaining_tickets_status — geteilt zwischen _TicketBar
/// (fixe Leiste unten) und _TicketInfoSection (Fließtext-Bereich weiter
/// oben), damit beide Stellen dieselbe Sprache sprechen.
({String label, Color color})? _ticketStatusInfo(
  String? status,
  AppColorsExtension colors,
  AppLocalizations l10n,
) => switch (status) {
  'available' => (label: l10n.ticketStatusAvailable, color: colors.success),
  'few_left' => (label: l10n.ticketStatusFewLeft, color: colors.warning),
  'sold_out' => (label: l10n.ticketStatusSoldOut, color: colors.error),
  'box_office_only' => (
    label: l10n.ticketStatusBoxOfficeOnly,
    color: colors.textSecondary,
  ),
  _ => null,
};

String _formatPrice(dynamic value) {
  final d = (value as num).toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
}

Map<String, String> _changeFieldLabels(AppLocalizations l10n) => {
  'start_datetime': l10n.eventChangeStartDatetime,
  'venue_id': l10n.eventChangeVenue,
  'status': l10n.eventChangeStatus,
};

String _formatChangeValue(AppLocalizations l10n, String field, String? value) {
  if (value == null) return '–';
  switch (field) {
    case 'start_datetime':
      final d = MunichTime.tryParse(value);
      if (d == null) return value;
      return l10n.eventDateTimeShort(
        '${d.day}.${d.month}.${d.year}',
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
      );
    case 'status':
      return _statusLabels(l10n)[value] ?? value;
    default:
      return value;
  }
}

/// "Was hat sich geändert" (Phase A.2, docs/09-feature-expansion-plan.md) —
/// speist sich aus event_changes, das der events_log_changes-Trigger
/// unabhängig vom Schreibpfad befüllt (Ingestion, Admin-Dashboard,
/// Enrichment-Functions). Zeigt nur die letzten 5 Änderungen, verschwindet
/// komplett ohne protokollierte Änderungen — bewusst warnend eingefärbt
/// (nicht neutral), damit ein verschobener/abgesagter Termin nicht in der
/// üblichen Textfarbe untergeht.
class _ChangesNotice extends StatelessWidget {
  const _ChangesNotice({required this.changes, required this.colors});

  final List changes;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final changeFieldLabels = _changeFieldLabels(l10n);

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: colors.warning),
              const SizedBox(width: 6),
              Text(
                l10n.eventRecentlyChanged,
                style: TextStyle(
                  color: colors.warning,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          for (final c in changes) ...[
            const SizedBox(height: 6),
            Text(
              // venue_id zeigt nur das Label, keine rohen UUIDs — der neue
              // Ortsname steht ohnehin bereits weiter oben auf der Seite.
              c['field_name'] == 'venue_id'
                  ? changeFieldLabels['venue_id']!
                  : '${changeFieldLabels[c['field_name']] ?? c['field_name']}: '
                        '${_formatChangeValue(l10n, c['field_name'] as String, c['old_value'] as String?)} → '
                        '${_formatChangeValue(l10n, c['field_name'] as String, c['new_value'] as String?)}',
              style: TextStyle(color: colors.textPrimary, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zusätzliche Ticket-Hinweise (Einlass, Altersbeschränkung, Ermäßigung,
/// Vorverkaufsgebühr) im scrollenden Inhalt statt in der fixen _TicketBar
/// unten — die hat schon einmal überlaufen, als sie mehr als eine Zeile
/// Inhalt bekam (siehe Kommentar beim SizedBox-Platzhalter weiter oben),
/// zusätzliche, meist leere optionale Felder gehören hier besser hin. Alle
/// Felder sind rein optional — die Sektion zeigt nur, was tatsächlich
/// gepflegt ist, und verschwindet komplett, wenn nichts davon vorliegt.
class _TicketInfoSection extends StatelessWidget {
  const _TicketInfoSection({required this.event, required this.colors});
  final Map<String, dynamic> event;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final statusInfo = _ticketStatusInfo(
      event['remaining_tickets_status'] as String?,
      colors,
      l10n,
    );
    final hints = [
      event['doors_info'],
      event['age_restriction'],
      event['discount_info'],
      event['presale_fee_info'],
      event['target_audience'],
      event['performance_language'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();

    if (statusInfo == null && hints.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (statusInfo != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusInfo.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusInfo.label,
                  style: TextStyle(
                    color: statusInfo.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          for (final hint in hints) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketBar extends StatelessWidget {
  const _TicketBar({required this.event, required this.colors});
  final Map<String, dynamic> event;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final priceMin = event['price_min'];
    final priceMax = event['price_max'];
    final isFree = event['is_free'] == true;
    final status = event['remaining_tickets_status'] as String?;
    // Ticket-Link individuell pro Event, nie von der Venue übernommen —
    // ticket_url ist bei so gut wie keinem Event gesetzt (die Quellen
    // liefern fast immer nur eine allgemeine Event-Seite statt eines
    // dedizierten Ticket-Links), website_url ist der Rückfall, damit der
    // Button nicht bei praktisch jedem Event fehlt.
    final link =
        (event['ticket_url'] as String?) ?? (event['website_url'] as String?);
    final soldOut = status == 'sold_out';
    final boxOfficeOnly = status == 'box_office_only';

    String priceText;
    if (isFree) {
      priceText = l10n.eventPriceFree;
    } else if (priceMin != null && priceMax != null && priceMin != priceMax) {
      priceText = l10n.eventPriceRange(
        _formatPrice(priceMin),
        _formatPrice(priceMax),
      );
    } else if (priceMin != null) {
      priceText = l10n.eventPriceFrom(_formatPrice(priceMin));
    } else {
      priceText = l10n.eventPriceOnRequest;
    }

    final statusInfo = _ticketStatusInfo(status, colors, l10n);
    // "Tickets kaufen" nur, wenn ein Kauf über den Link plausibel ist —
    // bei ausverkauft/nur Abendkasse wäre das irreführend, der Link bleibt
    // aber (führt oft trotzdem zu Restkarten-/Wartelisten-Infos).
    final buttonLabel = soldOut || boxOfficeOnly
        ? l10n.eventGoToPage
        : l10n.eventBuyTickets;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPaddingMobile,
        AppSpacing.md,
        AppSpacing.screenPaddingMobile,
        AppSpacing.md + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: colors.glass,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (statusInfo != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusInfo.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusInfo.label,
                  style: TextStyle(
                    color: statusInfo.color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                priceText,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (link != null)
                ElevatedButton(
                  onPressed: () {
                    // Ticketklick-Signal (docs/08-home-feed-recommendation-
                    // algorithm.md, Abschnitt 4.1/9) — stärkeres Intent-
                    // Signal als ein reiner Seitenaufruf, fließt in
                    // recommended_events()/hero_event() als zusätzliche
                    // Venue-/Mitwirkenden-Interesse-Evidenz ein. Nur für
                    // eingeloggte Nutzer (gleiche Einschränkung wie der
                    // event_views-Insert oben im Provider).
                    final userId =
                        Supabase.instance.client.auth.currentUser?.id;
                    if (userId != null) {
                      unawaited(
                        Supabase.instance.client.from('ticket_clicks').insert({
                          'user_id': userId,
                          'event_id': event['id'],
                        }),
                      );
                    }
                    launchUrl(
                      Uri.parse(link),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                  ),
                  child: Text(buttonLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
