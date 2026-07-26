import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/calendar/ics_export.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/detail_hero_background.dart';
import '../../../core/widgets/event_section.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/source_hint.dart';
import '../../home/application/home_providers.dart';

final _eventProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  slug,
) async {
  final event = await Supabase.instance.client
      .from('events')
      .select('''
        id, slug, title, subtitle, description_de,
        start_datetime, duration_minutes, has_intermission,
        ticket_url, price_min, price_max, price_currency, is_free,
        remaining_tickets_status, doors_info, age_restriction,
        discount_info, presale_fee_info, target_audience, performance_language,
        website_url, accessibility, status, image_urls,
        attribution_notice, attribution_license_url, last_verified_at,
        venues(id, slug, name, address_street, address_zip, address_city, photo_url, description_de),
        organizers(name),
        event_genres(genres(id, slug, label_de)),
        event_works(position, after_intermission, works(id, title, catalog_number, key_signature, instrumentation, movements, composer:persons(slug, full_name))),
        event_participants(role, persons(slug, full_name), ensembles(slug, name))
      ''')
      .eq('slug', slug)
      .neq('status', 'draft')
      .maybeSingle();

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

  return {...event, '_workSources': workSources};
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

String _formatVerifiedDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

const _statusLabel = {
  'scheduled': null,
  'sold_out': 'Ausverkauft',
  'cancelled': 'Abgesagt',
  'postponed': 'Verschoben',
};

const _roleLabel = {
  'komponist': 'Komponist:in',
  'dirigent': 'Dirigent:in',
  'solist': 'Solist:in',
  'chorleiter': 'Chorleiter:in',
  'moderator': 'Moderator:in',
};

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_eventProvider(slug));
    final colors = context.appColors;

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler beim Laden: $e')),
        data: (event) {
          if (event == null) {
            return Center(
              child: Text(
                'Veranstaltung nicht gefunden',
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
          final genreLabels = (event['event_genres'] as List)
              .map((g) => g['genres']?['label_de'] as String?)
              .whereType<String>()
              .toList();
          final primaryGenreId = (event['event_genres'] as List)
              .map((g) => g['genres']?['id'] as String?)
              .whereType<String>()
              .firstOrNull;

          final start = DateTime.tryParse(event['start_datetime'] ?? '');
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
          final statusBadge = _statusLabel[event['status']];
          final imageUrls = event['image_urls'] as List?;
          final photoUrl = (imageUrls != null && imageUrls.isNotEmpty)
              ? imageUrls.first as String?
              : null;

          return CustomScrollView(
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
                    tooltip: 'Zum Kalender hinzufügen',
                    onPressed: start == null
                        ? null
                        : () => IcsExport.shareEvent(
                            uid: event['id'],
                            title: event['title'] ?? '',
                            description: event['description_de'],
                            start: start,
                            durationMinutes: event['duration_minutes'],
                            location: venue != null
                                ? '${venue['name']}, ${venue['address_street']}, ${venue['address_zip']} ${venue['address_city']}'
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
                    tooltip: 'Teilen',
                    onPressed: () => Share.share(
                      '${event['title']}${venue != null ? ' · ${venue['name']}' : ''}'
                      '${event['website_url'] != null ? '\n${event['website_url']}' : ''}',
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      DetailHeroBackground(
                        photoUrl: photoUrl,
                        fallbackGenre: primaryGenre,
                        showGradient: false,
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
                        for (final label in genreLabels)
                          Chip(
                            label: Text(
                              label,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        if (event['is_free'] == true)
                          Chip(
                            label: const Text(
                              'Kostenlos',
                              style: TextStyle(fontSize: 11),
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
                          '${_weekday(start)}, ${start.day}.${start.month}.${start.year} · ${_time(start)} Uhr',
                        if (event['duration_minutes'] != null)
                          '${event['duration_minutes']} Min.${event['has_intermission'] == true ? ' inkl. Pause' : ''}',
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
                          '${venue['name']} — ${venue['address_street']}, ${venue['address_zip']} ${venue['address_city']}',
                          style: TextStyle(
                            color: colors.accentPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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
                    if (works.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Programm',
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
                                    workSources[w['works']?['id']] ?? const {},
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (participants.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Mitwirkende',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in participants)
                            _ParticipantChip(participant: p, colors: colors),
                        ],
                      ),
                    ],
                    if (accessibility.values.any((v) => v == true)) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Barrierefreiheit',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (accessibility['wheelchair'] == true)
                            const Chip(label: Text('Rollstuhlgerecht')),
                          if (accessibility['hearing_loop'] == true)
                            const Chip(label: Text('Induktionsschleife')),
                          if (accessibility['sign_language'] == true)
                            const Chip(label: Text('Gebärdensprache')),
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
                          'Zuletzt geprüft: '
                          '${_formatVerifiedDate(DateTime.parse(event['last_verified_at'] as String))}',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
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
                      title: 'Ähnliche Veranstaltungen',
                      events: similarEvents,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
            ],
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

  String _weekday(DateTime d) =>
      const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][d.weekday - 1];
  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Veranstaltungsort',
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
    final text = Text(
      'Datenquelle: $notice',
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (work['after_intermission'] == true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '— PAUSE —',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.accentSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (w['composer']?['full_name'] != null)
                Expanded(
                  flex: 2,
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
                      ),
                    ),
                  ),
                ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w['title'] ?? '',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Opus-/Werkverzeichnisnummer + Tonart nur, wenn
                    // recherchiert (siehe enrich-event-references) — rein
                    // optional, keine leere Zeile wenn nicht vorhanden.
                    if ((w['catalog_number'] as String?)?.isNotEmpty == true ||
                        (w['key_signature'] as String?)?.isNotEmpty == true)
                      Text(
                        [w['catalog_number'], w['key_signature']]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    // Instrumentierung (SATB/Bläserbesetzung/etc.) wird bewusst
                    // NICHT angezeigt — auf Nutzerwunsch: reines
                    // Rohbesetzungs-Detail ohne Mehrwert für Konzertbesucher,
                    // nicht das, was unter "Programm" erwartet wird. Das Feld
                    // wird weiterhin von enrich-work-profile befüllt (siehe
                    // dort), nur die Anzeige hier wurde entfernt.
                    if ((w['movements'] as List?)?.isNotEmpty == true)
                      Text(
                        (w['movements'] as List).whereType<String>().join(
                          ' · ',
                        ),
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  const _ParticipantChip({required this.participant, required this.colors});
  final dynamic participant;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final person = participant['persons'] as Map<String, dynamic>?;
    final ensemble = participant['ensembles'] as Map<String, dynamic>?;
    final name = person?['full_name'] ?? ensemble?['name'];
    if (name == null) return const SizedBox.shrink();
    final role = _roleLabel[participant['role']];

    return GestureDetector(
      onTap: () {
        if (person != null) {
          context.push('/person/${person['slug']}');
        } else if (ensemble != null) {
          context.push('/ensemble/${ensemble['slug']}');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colors.separator),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          role != null ? '$name · $role' : name,
          style: TextStyle(
            fontSize: 12.5,
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
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
) => switch (status) {
  'available' => (label: 'Tickets verfügbar', color: colors.success),
  'few_left' => (label: 'Nur noch wenige Tickets', color: colors.warning),
  'sold_out' => (label: 'Ausverkauft', color: colors.error),
  'box_office_only' => (
    label: 'Nur an der Abendkasse',
    color: colors.textSecondary,
  ),
  _ => null,
};

String _formatPrice(dynamic value) {
  final d = (value as num).toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
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
    final statusInfo = _ticketStatusInfo(
      event['remaining_tickets_status'] as String?,
      colors,
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
      priceText = 'Kostenlos';
    } else if (priceMin != null && priceMax != null && priceMin != priceMax) {
      priceText = '${_formatPrice(priceMin)}–${_formatPrice(priceMax)} €';
    } else if (priceMin != null) {
      priceText = 'ab ${_formatPrice(priceMin)} €';
    } else {
      priceText = 'Preis auf Anfrage';
    }

    final statusInfo = _ticketStatusInfo(status, colors);
    // "Tickets kaufen" nur, wenn ein Kauf über den Link plausibel ist —
    // bei ausverkauft/nur Abendkasse wäre das irreführend, der Link bleibt
    // aber (führt oft trotzdem zu Restkarten-/Wartelisten-Infos).
    final buttonLabel = soldOut || boxOfficeOnly
        ? 'Zur Veranstaltungsseite'
        : 'Tickets kaufen';

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
                  onPressed: () => launchUrl(
                    Uri.parse(link),
                    mode: LaunchMode.externalApplication,
                  ),
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
