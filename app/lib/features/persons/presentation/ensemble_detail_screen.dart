import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/gallery/entity_gallery_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/detail_hero_background.dart';
import '../../../core/widgets/entity_event_row.dart';
import '../../../core/widgets/entity_photo_gallery.dart';
import '../../../core/widgets/external_links_row.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/past_events_expansion.dart';
import '../../../core/widgets/report_content_sheet.dart';
import '../../../core/constants/role_labels.dart';
import '../../../core/widgets/similar_entities_row.dart';
import '../../../core/widgets/source_hint.dart';
import '../../../l10n/generated/app_localizations.dart';

final _ensembleProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  slug,
) async {
  final client = Supabase.instance.client;
  final ensemble = await client
      .from('ensembles')
      .select('*, home_venue:venues(name)')
      .eq('slug', slug)
      .maybeSingle();
  if (ensemble == null) return null;

  // parent_ensemble_id zeigt auf dieselbe Tabelle (Self-Join) — PostgREST
  // kann bei Self-Joins "gehört zu" (Vorwärts, ein Objekt) nicht zuverlässig
  // von "hat als Unter-Ensemble" (Rückwärts, mehrere) unterscheiden und
  // liefert über das Embedding immer die Rückwärts-Richtung. Deshalb hier
  // manuell in einem zweiten, einfachen Schritt aufgelöst statt embedded.
  final parentEnsembleId = ensemble['parent_ensemble_id'] as String?;
  if (parentEnsembleId != null) {
    ensemble['parent'] = await client
        .from('ensembles')
        .select('slug, name')
        .eq('id', parentEnsembleId)
        .maybeSingle();
  }

  final events = await client
      .from('event_participants')
      .select('events(id, slug, title, start_datetime, venues(name))')
      .eq('ensemble_id', ensemble['id'])
      .order('events(start_datetime)', ascending: true);

  final provenance = await client
      .from('field_provenance')
      .select('field_name, source_name, source_url, retrieved_at, confidence')
      .eq('entity_type', 'ensemble')
      .eq('entity_id', ensemble['id']);

  // "Ähnliche Ensembles" (Phase D.2) — gleicher Ensemble-Typ (Chor/
  // Orchester/Kammerensemble/...), nie sich selbst. Einfache Heuristik wie
  // bei Personen, kein eigener Empfehlungsdienst nötig.
  List<dynamic> similar = const [];
  if (ensemble['type'] != null) {
    similar = await client
        .from('ensembles')
        .select('slug, name, photo_url, type')
        .eq('type', ensemble['type'])
        .neq('id', ensemble['id'])
        .limit(8);
  }

  return {
    'ensemble': ensemble,
    'events': events,
    'sources': fieldSourcesFromRows(provenance),
    'similar': similar,
  };
});

class EnsembleDetailScreen extends ConsumerWidget {
  const EnsembleDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_ensembleProvider(slug));
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.errorLoadingGeneric(e.toString()))),
        data: (data) {
          if (data == null) {
            return Center(child: Text(l10n.ensembleNotFound));
          }
          final ensemble = data['ensemble'] as Map<String, dynamic>;
          final gallery = ref.watch(
            entityGalleryProvider((
              originType: 'ensemble',
              originId: ensemble['id'] as String,
            )),
          );
          final events = data['events'] as List;
          final sources = data['sources'] as Map<String, FieldSource>;
          final similar = data['similar'] as List;
          final now = MunichTime.now();
          final upcoming = events.where((row) {
            final start = MunichTime.tryParse(
              row['events']?['start_datetime'] ?? '',
            );
            return start != null && start.isAfter(now);
          }).toList();
          final past = events
              .where((row) {
                final start = MunichTime.tryParse(
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
                            fallbackGenre: EventGenre.orchester,
                          )
                        : DetailHeroBackground(
                            photoUrl: ensemble['photo_url'] as String?,
                            fallbackGenre: EventGenre.orchester,
                          ),
                    orElse: () => DetailHeroBackground(
                      photoUrl: ensemble['photo_url'] as String?,
                      fallbackGenre: EventGenre.orchester,
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
                      ensemble['name'] ?? '',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        ensembleTypeLabels(l10n)[ensemble['type']] ??
                            ensemble['type'],
                        if (ensemble['founded_year'] != null)
                          l10n.ensembleFoundedYear(
                            '${ensemble['founded_year']}',
                          ),
                        if (ensemble['member_count'] != null)
                          l10n.ensembleMemberCount(
                            ensemble['member_count'] as int,
                          ),
                        if (ensemble['home_venue']?['name'] != null)
                          ensemble['home_venue']['name'],
                      ].join(' · '),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (ensemble['parent'] != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      GestureDetector(
                        onTap: () => context.push(
                          '/ensemble/${ensemble['parent']['slug']}',
                        ),
                        child: Text(
                          'Teil von ${ensemble['parent']['name']}',
                          style: TextStyle(
                            color: colors.accentPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (ensemble['description_de'] != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      SectionHeaderWithSource(
                        title: l10n.ensembleAbout,
                        colors: colors,
                        source: sources['description_de'],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        ensemble['description_de'],
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (ensemble['leadership_de'] != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              ensemble['leadership_de'],
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SourceHintIcon(source: sources['leadership_de']),
                        ],
                      ),
                    ],
                    if (ensemble['residency_de'] != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              ensemble['residency_de'],
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                          SourceHintIcon(source: sources['residency_de']),
                        ],
                      ),
                    ],
                    if (ensemble['repertoire_de'] != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      SectionHeaderWithSource(
                        title: l10n.ensembleRepertoire,
                        colors: colors,
                        source: sources['repertoire_de'],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        ensemble['repertoire_de'],
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ExternalLinksRow(
                      websiteUrl: ensemble['website_url'] as String?,
                      socialLinks:
                          ensemble['social_links'] as Map<String, dynamic>?,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      l10n.ensembleUpcomingEvents,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (upcoming.isEmpty)
                      Text(
                        l10n.ensembleNothingPlanned,
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
                              child: _EnsembleEventRow(
                                row: row,
                                colors: colors,
                              ),
                            ),
                        ],
                      ),
                    if (past.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      PastEventsExpansion(
                        rows: [
                          for (final row in past)
                            _EnsembleEventRow(row: row, colors: colors),
                        ],
                      ),
                    ],
                    if (similar.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        l10n.ensembleSimilar,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SimilarEnsemblesRow(entries: similar),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    ReportContentLink(
                      entityType: 'ensemble',
                      entityId: ensemble['id'] as String,
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

class _EnsembleEventRow extends StatelessWidget {
  const _EnsembleEventRow({required this.row, required this.colors});
  final dynamic row;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final event = row['events'] as Map<String, dynamic>?;
    if (event == null) return const SizedBox.shrink();
    return EntityEventRow(
      title: event['title'] ?? '',
      slug: event['slug'] as String? ?? '',
      start: MunichTime.tryParse(event['start_datetime']),
      subtitle: event['venues']?['name'] as String?,
    );
  }
}
