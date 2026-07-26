import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/external_maps.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/detail_hero_background.dart';
import '../../../core/widgets/external_links_row.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/source_hint.dart';

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
      .order('start_datetime');

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

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler beim Laden: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Venue nicht gefunden'));
          }
          final venue = data['venue'] as Map<String, dynamic>;
          final events = data['events'] as List;
          final latLng = data['latLng'] as Map<String, dynamic>?;
          final sources = data['sources'] as Map<String, FieldSource>;
          final accessibility =
              (venue['accessibility'] as Map<String, dynamic>?) ?? {};
          final now = DateTime.now();
          final upcoming = events.where((e) {
            final start = DateTime.tryParse(e['start_datetime'] ?? '');
            return start != null && start.isAfter(now);
          }).toList();

          final address =
              '${venue['address_street']}, ${venue['address_zip']} ${venue['address_city']}';

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: colors.backgroundPrimary,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: DetailHeroBackground(
                    photoUrl: venue['photo_url'] as String?,
                    fallbackGenre: EventGenre.kirchenmusik,
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
                        TextButton(
                          onPressed: latLng == null
                              ? null
                              : () => openExternalMaps(
                                  lat: (latLng['lat'] as num).toDouble(),
                                  lng: (latLng['lng'] as num).toDouble(),
                                  name: venue['name'] as String? ?? '',
                                ),
                          child: const Text('Route'),
                        ),
                      ],
                    ),
                    if (venue['capacity'] != null ||
                        venue['venue_type'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          _venueTypeLabel(venue['venue_type'] as String?),
                          if (venue['capacity'] != null)
                            '${venue['capacity']} Plätze',
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
                        title: 'Geschichte',
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
                          if (accessibility['step_free'] == true)
                            const Chip(label: Text('Stufenloser Zugang')),
                          if (accessibility['elevator'] == true)
                            const Chip(label: Text('Aufzug')),
                          if (accessibility['accessible_toilet'] == true)
                            const Chip(label: Text('Barrierefreies WC')),
                        ],
                      ),
                    ],
                    if (venue['parking_info_de'] != null ||
                        (venue['mvv_stops'] as List?)?.isNotEmpty == true ||
                        venue['arrival_info_de'] != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Anreise',
                        style: Theme.of(context).textTheme.headlineSmall,
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
                        title: 'Praktische Hinweise',
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
                      'Kommende Veranstaltungen',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (upcoming.isEmpty)
                      Text(
                        'Aktuell nichts geplant.',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 13,
                        ),
                      )
                    else
                      DetailCard(
                        children: [
                          for (final event in upcoming)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: _VenueEventRow(
                                event: event,
                                colors: colors,
                              ),
                            ),
                        ],
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
String? _venueTypeLabel(String? type) => switch (type) {
  'konzertsaal' => 'Konzertsaal',
  'kirche' => 'Kirche',
  'theater' => 'Theater',
  'museum' => 'Museum',
  'schloss' => 'Schloss',
  'kulturzentrum' => 'Kulturzentrum',
  'sonstiges' => null,
  _ => null,
};

class _MvvStopRow extends StatelessWidget {
  const _MvvStopRow({required this.stop, required this.colors});

  final Map<String, dynamic> stop;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
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
                    walkMinutes != null ? '$walkMinutes Min. zu Fuß' : null,
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

class _VenueEventRow extends StatelessWidget {
  const _VenueEventRow({required this.event, required this.colors});
  final dynamic event;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(event['start_datetime'] ?? '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        event['title'] ?? '',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      subtitle: start != null
          ? Text(
              '${start.day}.${start.month}.${start.year}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
            )
          : null,
      onTap: () => context.push('/event/${event['slug']}'),
    );
  }
}
