import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/gallery/entity_gallery_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/entity_event_row.dart';
import '../../../core/widgets/entity_photo_gallery.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/source_hint.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Programm-Explorer (Phase C.1, docs/09-feature-expansion-plan.md,
/// Nutzerwunsch Punkt 6): "Werke sollten nicht nur als Freitext erscheinen,
/// sondern als eigene Entitäten... Nutzer könnten beispielsweise alle
/// kommenden Aufführungen der 5. Sinfonie von Mahler finden." works hat
/// bereits fast alle gewünschten Felder (siehe enrich-work-profile) — hier
/// nur gebündelt dargestellt, plus die Liste aller Aufführungen über
/// event_works.
final _workProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  workId,
) async {
  final client = Supabase.instance.client;
  final work = await client
      .from('works')
      .select('''
        id, title, catalog_number, key_signature, composition_year,
        duration_minutes, description_de, genre, instrumentation,
        alternative_titles, movements,
        composer:persons(slug, full_name)
      ''')
      .eq('id', workId)
      .maybeSingle();
  if (work == null) return null;

  final performances = await client
      .from('event_works')
      .select('events(id, slug, title, start_datetime, venues(name))')
      .eq('work_id', workId);

  final provenance = await client
      .from('field_provenance')
      .select('field_name, source_name, source_url, retrieved_at, confidence')
      .eq('entity_type', 'work')
      .eq('entity_id', workId);

  return {
    'work': work,
    'performances': performances,
    'sources': fieldSourcesFromRows(provenance),
  };
});

class WorkDetailScreen extends ConsumerWidget {
  const WorkDetailScreen({required this.workId, super.key});

  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_workProvider(workId));
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.workAppBarTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.errorLoadingGeneric(e.toString()))),
        data: (data) {
          if (data == null) {
            return Center(
              child: Text(
                l10n.workNotFound,
                style: TextStyle(color: colors.textSecondary),
              ),
            );
          }
          final work = data['work'] as Map<String, dynamic>;
          final sources = data['sources'] as Map<String, FieldSource>;
          final composer = work['composer'] as Map<String, dynamic>?;
          final now = MunichTime.now();
          final performances = (data['performances'] as List)
              .map((p) => p['events'] as Map<String, dynamic>?)
              .whereType<Map<String, dynamic>>()
              .toList();
          final upcoming =
              performances.where((e) {
                final start = MunichTime.tryParse(e['start_datetime']);
                return start != null && start.isAfter(now);
              }).toList()..sort(
                (a, b) =>
                    DateTime.parse(a['start_datetime'])
                        .compareTo(DateTime.parse(b['start_datetime'])),
              );
          final past =
              performances.where((e) {
                final start = MunichTime.tryParse(e['start_datetime']);
                return start != null && start.isBefore(now);
              }).toList()..sort(
                (a, b) =>
                    DateTime.parse(b['start_datetime'])
                        .compareTo(DateTime.parse(a['start_datetime'])),
              );

          final alternativeTitles =
              (work['alternative_titles'] as List?)?.cast<String>() ?? const [];
          final movements =
              (work['movements'] as List?)?.cast<String>() ?? const [];
          final gallery = ref.watch(
            entityGalleryProvider((originType: 'work', originId: workId)),
          );
          final galleryImages = gallery.valueOrNull ?? const [];

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPaddingMobile,
              AppSpacing.lg,
              AppSpacing.screenPaddingMobile,
              AppSpacing.xxl,
            ),
            children: [
              if (galleryImages.isNotEmpty) ...[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: EntityPhotoGallery(
                      images: galleryImages,
                      fallbackGenre: EventGenre.kammermusik,
                      showGradient: false,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Text(
                work['title'] ?? '',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              if (alternativeTitles.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  alternativeTitles.join(' · '),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (composer?['full_name'] != null)
                Semantics(
                  button: composer?['slug'] != null,
                  link: composer?['slug'] != null,
                  child: GestureDetector(
                    onTap: composer?['slug'] != null
                        ? () => context.push('/person/${composer!['slug']}')
                        : null,
                    child: Text(
                      composer!['full_name'],
                      style: TextStyle(
                        color: composer['slug'] != null
                            ? colors.accentPrimary
                            : colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                [
                  work['catalog_number'],
                  work['key_signature'],
                  if (work['composition_year'] != null)
                    '${work['composition_year']}',
                  work['genre'],
                  if (work['duration_minutes'] != null)
                    l10n.workMinutes(work['duration_minutes'] as int),
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
              ),
              if (work['description_de'] != null) ...[
                const SizedBox(height: AppSpacing.lg),
                SectionHeaderWithSource(
                  title: l10n.workAbout,
                  colors: colors,
                  source: sources['description_de'],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  work['description_de'],
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              if (work['instrumentation'] != null) ...[
                const SizedBox(height: AppSpacing.md),
                SectionHeaderWithSource(
                  title: l10n.workInstrumentation,
                  colors: colors,
                  source: sources['instrumentation'],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  work['instrumentation'],
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
              if (movements.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                SectionHeaderWithSource(
                  title: l10n.workMovements,
                  colors: colors,
                  source: sources['movements'],
                ),
                const SizedBox(height: AppSpacing.sm),
                DetailCard(
                  children: [
                    for (var i = 0; i < movements.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Text(
                          '${i + 1}. ${movements[i]}',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                l10n.workUpcomingPerformances,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (upcoming.isEmpty)
                Text(
                  l10n.workNothingPlanned,
                  style: TextStyle(color: colors.textTertiary, fontSize: 13),
                )
              else
                DetailCard(
                  children: [
                    for (final event in upcoming)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: EntityEventRow(
                          title: event['title'] ?? '',
                          slug: event['slug'] as String? ?? '',
                          start: MunichTime.tryParse(
                            event['start_datetime'] ?? '',
                          ),
                          subtitle: event['venues']?['name'] as String?,
                        ),
                      ),
                  ],
                ),
              if (past.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.workPastPerformances(past.length),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
