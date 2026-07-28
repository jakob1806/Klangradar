import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/gallery/entity_gallery_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/detail_hero_background.dart';
import '../../../core/widgets/entity_photo_gallery.dart';
import '../../../core/widgets/external_links_row.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/past_events_expansion.dart';
import '../../../core/widgets/source_hint.dart';

final _personProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  slug,
) async {
  final client = Supabase.instance.client;
  final person = await client
      .from('persons')
      .select()
      .eq('slug', slug)
      .maybeSingle();
  if (person == null) return null;

  final events = await client
      .from('event_participants')
      .select('role, events(id, slug, title, start_datetime, venues(name))')
      .eq('person_id', person['id'])
      .order('events(start_datetime)', ascending: true);

  final provenance = await client
      .from('field_provenance')
      .select('field_name, source_name, source_url, retrieved_at, confidence')
      .eq('entity_type', 'person')
      .eq('entity_id', person['id']);

  return {
    'person': person,
    'events': events,
    'sources': fieldSourcesFromRows(provenance),
  };
});

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_personProvider(slug));
    final colors = context.appColors;

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler beim Laden: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Person nicht gefunden'));
          }
          final person = data['person'] as Map<String, dynamic>;
          final gallery = ref.watch(
            entityGalleryProvider((
              originType: 'person',
              originId: person['id'] as String,
            )),
          );
          final events = data['events'] as List;
          final sources = data['sources'] as Map<String, FieldSource>;
          final roles = (person['roles'] as List?)?.cast<String>() ?? [];
          final now = DateTime.now();
          final upcoming = events.where((row) {
            final start = DateTime.tryParse(
              row['events']?['start_datetime'] ?? '',
            );
            return start != null && start.isAfter(now);
          }).toList();
          final past = events
              .where((row) {
                final start = DateTime.tryParse(
                  row['events']?['start_datetime'] ?? '',
                );
                return start != null && start.isBefore(now);
              })
              .toList()
              .reversed // jüngste zuerst statt älteste zuerst
              .take(20)
              .toList();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 293,
                pinned: true,
                backgroundColor: colors.backgroundPrimary,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: gallery.maybeWhen(
                    data: (images) => images.isNotEmpty
                        ? EntityPhotoGallery(
                            images: images,
                            fallbackGenre: EventGenre.kammermusik,
                          )
                        : DetailHeroBackground(
                            photoUrl: person['photo_url'] as String?,
                            fallbackGenre: EventGenre.kammermusik,
                          ),
                    orElse: () => DetailHeroBackground(
                      photoUrl: person['photo_url'] as String?,
                      fallbackGenre: EventGenre.kammermusik,
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
                      person['full_name'] ?? '',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    if (roles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: roles
                            .map(
                              (r) => Chip(
                                label: Text(
                                  r,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (person['nationality'] != null ||
                        person['instrument'] != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        [
                          person['nationality'],
                          person['instrument'],
                          if (person['birth_date'] != null)
                            '* ${(person['birth_date'] as String).substring(0, 4)}'
                                '${person['death_date'] != null ? ' † ${(person['death_date'] as String).substring(0, 4)}' : ''}',
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (person['biography_de'] != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      SectionHeaderWithSource(
                        title: 'Biografie',
                        colors: colors,
                        source: sources['biography_de'],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        person['biography_de'],
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (person['current_roles_de'] != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        person['current_roles_de'],
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (person['education_career_de'] != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      SectionHeaderWithSource(
                        title: 'Ausbildung & Karriere',
                        colors: colors,
                        source: sources['education_career_de'],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        person['education_career_de'],
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ExternalLinksRow(
                      websiteUrl: person['website_url'] as String?,
                      wikipediaUrl: person['wikipedia_url'] as String?,
                      socialLinks:
                          person['social_links'] as Map<String, dynamic>?,
                    ),
                    _BioSection(
                      title: 'Repertoire-Schwerpunkte',
                      entries: person['repertoire_highlights'] as List?,
                      colors: colors,
                      lineOf: (e) => [
                        e['title'],
                        e['note'],
                      ].whereType<String>().join(' — '),
                    ),
                    _BioSection(
                      title: 'Auszeichnungen',
                      entries: person['awards'] as List?,
                      colors: colors,
                      lineOf: (e) => [
                        [
                          if (e['year'] != null) '${e['year']}',
                          e['title'],
                        ].whereType<String>().join(' · '),
                        e['note'],
                      ].whereType<String>().join(' — '),
                    ),
                    _BioSection(
                      title: 'Bekannte Aufnahmen',
                      entries: person['notable_recordings'] as List?,
                      colors: colors,
                      lineOf: (e) => [
                        e['title'],
                        e['label'],
                        if (e['year'] != null) '${e['year']}',
                      ].whereType<String>().join(' · '),
                      urlOf: (e) => e['url'] as String?,
                    ),
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
                          for (final row in upcoming)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: _EventRow(row: row, colors: colors),
                            ),
                        ],
                      ),
                    if (past.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      PastEventsExpansion(
                        rows: [
                          for (final row in past)
                            _EventRow(row: row, colors: colors),
                        ],
                      ),
                    ],
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

/// Titelierter Abschnitt für strukturierte Bio-Listen (Repertoire,
/// Auszeichnungen, Aufnahmen) — rendert nichts, wenn der jsonb-Array leer
/// ist. `lineOf` formatiert einen Eintrag zu einer Zeile, `urlOf` macht die
/// Zeile optional antippbar (z.B. Link zur Aufnahme).
class _BioSection extends StatelessWidget {
  const _BioSection({
    required this.title,
    required this.entries,
    required this.colors,
    required this.lineOf,
    this.urlOf,
  });

  final String title;
  final List<dynamic>? entries;
  final AppColorsExtension colors;
  final String Function(Map<String, dynamic>) lineOf;
  final String? Function(Map<String, dynamic>)? urlOf;

  @override
  Widget build(BuildContext context) {
    final items = (entries ?? const []).cast<Map<String, dynamic>>();
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _BioEntryLine(
                text: lineOf(e),
                url: urlOf?.call(e),
                colors: colors,
              ),
            ),
        ],
      ),
    );
  }
}

class _BioEntryLine extends StatelessWidget {
  const _BioEntryLine({required this.text, required this.colors, this.url});

  final String text;
  final String? url;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      '·  $text',
      style: TextStyle(
        color: url != null ? colors.accentPrimary : colors.textPrimary,
        fontSize: 13.5,
        height: 1.4,
      ),
    );
    if (url == null) return child;
    return GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: child,
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.row, required this.colors});
  final dynamic row;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final event = row['events'] as Map<String, dynamic>?;
    if (event == null) return const SizedBox.shrink();
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
      subtitle: Text(
        [
          if (event['venues']?['name'] != null) event['venues']['name'],
          if (start != null) '${start.day}.${start.month}.${start.year}',
        ].join(' · '),
        style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
      ),
      onTap: () => context.push('/event/${event['slug']}'),
    );
  }
}
