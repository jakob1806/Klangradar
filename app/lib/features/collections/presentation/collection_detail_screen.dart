import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/application/home_providers.dart';

final _collectionProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, slug) async {
      final client = Supabase.instance.client;
      final collection = await client
          .from('editorial_collections')
          .select('id, title, subtitle, description_de, cover_image_url')
          .eq('slug', slug)
          .maybeSingle();
      if (collection == null) return null;

      final rows = await client
          .from('editorial_collection_events')
          .select('position, events($homeEventColumns)')
          .eq('collection_id', collection['id'])
          .order('position', ascending: true);

      final events = (rows as List)
          .map((r) => r['events'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .map(HomeEventItem.fromRow)
          .toList();

      return {'collection': collection, 'events': events};
    });

class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_collectionProvider(slug));
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.collectionAppBarTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.errorLoadingGeneric(e.toString()))),
        data: (data) {
          if (data == null) {
            return Center(
              child: Text(
                l10n.collectionNotFound,
                style: TextStyle(color: colors.textSecondary),
              ),
            );
          }
          final collection = data['collection'] as Map<String, dynamic>;
          final events = data['events'] as List<HomeEventItem>;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPaddingMobile,
              AppSpacing.lg,
              AppSpacing.screenPaddingMobile,
              AppSpacing.xxl,
            ),
            children: [
              Text(
                collection['title'] ?? '',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              if (collection['subtitle'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  collection['subtitle'],
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
              ],
              if (collection['description_de'] != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  collection['description_de'],
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (events.isEmpty)
                Text(
                  l10n.collectionNoEvents,
                  style: TextStyle(color: colors.textTertiary, fontSize: 13),
                )
              else
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: GenreArtwork(genre: e.genre),
                        ),
                      ),
                      title: Text(
                        e.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        e.venueAndTime,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                      onTap: () => context.push('/event/${e.slug}'),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
