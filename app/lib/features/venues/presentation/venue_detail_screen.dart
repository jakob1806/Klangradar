import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/gallery/entity_gallery_providers.dart';
import '../../../core/interests/interests_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/utils/external_maps.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/detail_hero_background.dart';
import '../../../core/widgets/entity_event_row.dart';
import '../../../core/widgets/entity_photo_gallery.dart';
import '../../../core/widgets/external_links_row.dart';
import '../../../core/widgets/follow_button.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/report_content_sheet.dart';
import '../../../core/widgets/source_hint.dart';
import '../../../l10n/generated/app_localizations.dart';

final _venueProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  slug,
) async {
  final client = Supabase.instance.client;
  final venue = await client
      .from('venues')
      .select()
      .eq('slug', slug)
      .maybeSingle();
  if (venue == null) return null;

  // Separater RPC-Aufruf statt lat/lng in die venues-Query zu mischen —
  // PostgREST liefert geography-Spalten sonst als WKB-Hex, dieselbe RPC
  // nutzt schon der Karten-Tab und das Admin-Dashboard (venue_with_latlng).
  final events = await client
      .from('events')
      .select('id, slug, title, start_datetime')
      .eq('venue_id', venue['id'])
      .neq('status', 'draft')
      .order('start_datetime', ascending: true);

  final latLng = await client
      .rpc('venue_with_latlng', params: {'p_id': venue['id']})
      .maybeSingle();

  // Quellenbelege pro automatisiert recherchiertem Feld (Phase 6: "dezente,
  // aber nachvollziehbare Quellenhinweise") — siehe _shared/provenance.ts
  // auf Backend-Seite, hier nur gelesen, nie geschrieben.
  final provenance = await client
      .from('field_provenance')
      .select('field_name, source_name, source_url, retrieved_at, confidence')
      .eq('entity_type', 'venue')
      .eq('entity_id', venue['id']);

  return {
    'venue': venue,
    'events': events,
    'latLng': latLng,
    'sources': fieldSourcesFromRows(provenance),
  };
});

class VenueDetailScreen extends ConsumerWidget {
  const VenueDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_venueProvider(slug));
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.errorLoadingGeneric(e.toString()))),
        data: (data) {
          if (data == null) {
            return Center(child: Text(l10n.venueNotFound));
          }
          final venue = data['venue'] as Map<String, dynamic>;
          final gallery = ref.watch(
            entityGalleryProvider((
              originType: 'venue',
              originId: venue['id'] as String,
            )),
          );
          final events = data['events'] as List;
          final latLng = data['latLng'] as Map<String, dynamic>?;
          final sources = data['sources'] as Map<String, FieldSource>;
          final accessibility =
              (venue['accessibility'] as Map<String, dynamic>?) ?? {};
          final now = MunichTime.now();
          final upcoming = events.where((e) {
            final start = MunichTime.tryParse(e['start_datetime']);
            return start != null && start.isAfter(now);
          }).toList();

          final address =
              '${venue['address_street']}, ${venue['address_zip']} ${venue['address_city']}';

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 293,
                pinned: true,
                backgroundColor: colors.backgroundPrimary,
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  FollowButton(
                    category: InterestCategory.venue,
                    entityId: venue['id'] as String,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: gallery.maybeWhen(
                    data: (images) => images.isNotEmpty
                        ? EntityPhotoGallery(
                            images: images,
                            fallbackGenre: EventGenre.kirchenmusik,
                          )
                        : DetailHeroBackground(
                            photoUrl: venue['photo_url'] as String?,
                            fallbackGenre: EventGenre.kirchenmusik,
                          ),
                    orElse: () => DetailHeroBackground(
                      photoUrl: venue['photo_url'] as String?,
                      fallbackGenre: EventGenre.kirchenmusik,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPaddingMobile,
                  AppSpacing.lg,
                  AppSpacing.screenPaddingMobile,
                  AppSpacing.xxxl,
                ),
                sliver: SliverList.list(
                  children: [
                    Text(
                      venue['name'] ?? '',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            // Stadtteil ergänzt die Adresse, wenn recherchiert
                            // (siehe enrich-venue-details) — rein additiv,
                            // die Adresse selbst bleibt unverändert.
                            venue['district'] != null
                                ? '$address · ${venue['district']}'
                                : address,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        _RouteButton(
                          onPressed: latLng == null
                              ? null
                              : () => openExternalMaps(
                                  lat: (latLng['lat'] as num).toDouble(),
                                  lng: (latLng['lng'] as num).toDouble(),
                                  name: venue['name'] as String? ?? '',
                                ),
                        ),
                      ],
                    ),
                    if (venue['capacity'] != null ||
                        venue['venue_type'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          _venueTypeLabel(l10n, venue['venue_type'] as String?),
                          if (venue['capacity'] != null)
                            l10n.venueSeats(venue['capacity'] as int),
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (venue['description_de'] != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        venue['description_de'],
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                    // Geschichte/künstlerisches Profil — eigener Abschnitt,
                    // getrennt vom Kurzporträt (description_de), da beide
                    // unterschiedliche Zwecke haben (siehe
                    // enrich-venue-details: historyDe ist bewusst ein
                    // eigenes Feld, kein Ersatz für description_de).
                    if (venue['history_de'] != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      SectionHeaderWithSource(
                        title: l10n.venueHistory,
                        colors: colors,
                        source: sources['history_de'],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        venue['history_de'],
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ExternalLinksRow(
                      websiteUrl: venue['website_url'] as String?,
                      socialLinks:
                          venue['social_links'] as Map<String, dynamic>?,
                    ),
                    if (venue['phone'] != null || venue['email'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          venue['phone'],
                          venue['email'],
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (accessibility.values.any((v) => v == true)) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        l10n.venueAccessibilityTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (accessibility['wheelchair'] == true)
                            Chip(
                              label: Text(l10n.venueAccessibilityWheelchair),
                            ),
                          if (accessibility['hearing_loop'] == true)
                            Chip(
                              label: Text(l10n.venueAccessibilityHearingLoop),
                            ),
                          if (accessibility['sign_language'] == true)
                            Chip(
                              label: Text(l10n.venueAccessibilitySignLanguage),
                            ),
                          if (accessibility['step_free'] == true)
                            Chip(label: Text(l10n.venueAccessibilityStepFree)),
                          if (accessibility['elevator'] == true)
                            Chip(label: Text(l10n.venueAccessibilityElevator)),
                          if (accessibility['accessible_toilet'] == true)
                            Chip(label: Text(l10n.venueAccessibilityToilet)),
                        ],
                      ),
                    ],
                    if (venue['parking_info_de'] != null ||
                        (venue['mvv_stops'] as List?)?.isNotEmpty == true ||
                        venue['arrival_info_de'] != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeaderWithSource(
                        title: l10n.venueArrival,
                        colors: colors,
                        source: sources['arrival_info_de'],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DetailCard(
                        dividers: false,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((venue['mvv_stops'] as List?)?.isNotEmpty ==
                                    true)
                                  for (final stop in venue['mvv_stops'] as List)
                                    _MvvStopRow(
                                      stop: stop as Map<String, dynamic>,
                                      colors: colors,
                                    ),
                                if (venue['parking_info_de'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      venue['parking_info_de'],
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                // Fahrrad/Taxi/Fußweg — ergänzt MVV/Parken
                                // (oben), nie ein Ersatz dafür (siehe
                                // enrich-venue-details).
                                if (venue['arrival_info_de'] != null)
                                  Text(
                                    venue['arrival_info_de'],
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (venue['doors_info_de'] != null ||
                        venue['catering_info_de'] != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      SectionHeaderWithSource(
                        title: l10n.venuePracticalInfo,
                        colors: colors,
                        source:
                            sources['doors_info_de'] ??
                            sources['catering_info_de'],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DetailCard(
                        children: [
                          for (final hint in [
                            venue['doors_info_de'],
                            venue['catering_info_de'],
                          ].whereType<String>())
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Text(
                                hint,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      l10n.venueUpcomingEvents,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (upcoming.isEmpty)
                      Text(
                        l10n.venueNothingPlanned,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 13,
                        ),
                      )
                    else
                      _GroupedUpcomingEvents(events: upcoming),
                    const SizedBox(height: AppSpacing.lg),
                    ReportContentLink(
                      entityType: 'venue',
                      entityId: venue['id'] as String,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Muss zu den venue_type-Werten in enrich-venue-details/index.ts passen.
String? _venueTypeLabel(AppLocalizations l10n, String? type) => switch (type) {
  'konzertsaal' => l10n.venueTypeConcertHall,
  'kirche' => l10n.venueTypeChurch,
  'theater' => l10n.venueTypeTheater,
  'museum' => l10n.venueTypeMuseum,
  'schloss' => l10n.venueTypeCastle,
  'kulturzentrum' => l10n.venueTypeCulturalCenter,
  'sonstiges' => null,
  _ => null,
};

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

class _MonthGroup {
  _MonthGroup({required this.year, required this.month, required this.events});

  final int year;
  final int month;
  final List<dynamic> events;
}

/// Nutzerfeedback: "bei der detailansicht einer venue sind ja die kommenden
/// konzerte nach wie vor alle in einer langen liste angeordnet" — bei
/// Sälen mit über 100 kommenden Terminen (live geprüft: Philharmonie,
/// Herkulessaal) war das eine kaum scrollbare Wand aus Zeilen. Gruppierung
/// nach Monat statt eines Kalendergrids: bei stark unterschiedlicher
/// Terminanzahl pro Monat (mancher Monat 1 Termin, mancher 20) bleibt eine
/// Liste besser scanbar als ein Raster mit vielen leeren Zellen. Nur der
/// nächste (chronologisch erste) Monat startet aufgeklappt, alle weiteren
/// eingeklappt mit Anzahl — ein Blick auf "wann geht's als Nächstes los"
/// bleibt sofort sichtbar, ohne die restlichen Monate zu verstecken.
class _GroupedUpcomingEvents extends StatefulWidget {
  const _GroupedUpcomingEvents({required this.events});

  final List<dynamic> events;

  @override
  State<_GroupedUpcomingEvents> createState() => _GroupedUpcomingEventsState();
}

class _GroupedUpcomingEventsState extends State<_GroupedUpcomingEvents> {
  final Set<int> _expanded = {0};

  List<_MonthGroup> _groupByMonth() {
    final groups = <_MonthGroup>[];
    for (final event in widget.events) {
      final start = MunichTime.tryParse(event['start_datetime']);
      if (start == null) continue;
      if (groups.isEmpty ||
          groups.last.year != start.year ||
          groups.last.month != start.month) {
        groups.add(
          _MonthGroup(year: start.year, month: start.month, events: []),
        );
      }
      groups.last.events.add(event);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.appColors;
    final groups = _groupByMonth();
    final monthNames = _fullMonthNames(l10n);

    return Column(
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _MonthGroupCard(
            label: '${monthNames[groups[i].month - 1]} ${groups[i].year}',
            events: groups[i].events,
            expanded: _expanded.contains(i),
            colors: colors,
            onToggle: () => setState(() {
              if (!_expanded.remove(i)) _expanded.add(i);
            }),
          ),
        ],
      ],
    );
  }
}

class _MonthGroupCard extends StatelessWidget {
  const _MonthGroupCard({
    required this.label,
    required this.events,
    required this.expanded,
    required this.colors,
    required this.onToggle,
  });

  final String label;
  final List<dynamic> events;
  final bool expanded;
  final AppColorsExtension colors;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return DetailCard(
      dividers: false,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$label · ${events.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: EntityEventRow(
                title: event['title'] ?? '',
                slug: event['slug'] as String? ?? '',
                start: MunichTime.tryParse(event['start_datetime']),
              ),
            ),
      ],
    );
  }
}

class _MvvStopRow extends StatelessWidget {
  const _MvvStopRow({required this.stop, required this.colors});

  final Map<String, dynamic> stop;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines =
        (stop['lines'] as List?)?.whereType<String>().toList() ?? const [];
    final walkMinutes = stop['walk_minutes'] as int?;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.directions_transit_rounded,
            size: 18,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    stop['name'] as String?,
                    walkMinutes != null
                        ? l10n.venueWalkMinutes(walkMinutes)
                        : null,
                  ].whereType<String>().join(' · '),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final line in lines)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.separator),
                          ),
                          child: Text(
                            line,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Runder, modern gestalteter Routen-Button im Akzent-Rot der App (Nutzer-
/// anfrage: "den Button der Route bei Venues etwas auffälliger, passend im
/// eh schon roten Stil farblich hinterlegen, runder Button, modernes
/// Design") — ersetzt den bisher unauffälligen TextButton.
class _RouteButton extends StatelessWidget {
  const _RouteButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final disabled = onPressed == null;

    return Material(
      color: disabled ? colors.separator : colors.accentPrimary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_rounded,
                size: 18,
                color: disabled ? colors.textSecondary : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.venueRoute,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: disabled ? colors.textSecondary : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
