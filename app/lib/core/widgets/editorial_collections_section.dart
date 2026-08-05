import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Redaktionelle Themensammlungen (Phase D.1, docs/09-feature-expansion-
/// plan.md, Nutzerwunsch Punkt 11: "Höhepunkte der Woche... thematische
/// Sammlungen, Festivalübersichten") — nur veröffentlichte Sammlungen
/// (RLS filtert das ohnehin serverseitig, is_published-Spalte bleibt hier
/// nur zur Doku).
final editorialCollectionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await Supabase.instance.client
          .from('editorial_collections')
          .select('id, slug, title, subtitle, cover_image_url')
          .order('sort_order', ascending: true);
      return (rows as List).cast<Map<String, dynamic>>();
    });

class EditorialCollectionsSection extends ConsumerWidget {
  const EditorialCollectionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(editorialCollectionsProvider);
    final colors = context.appColors;
    final collections = async.valueOrNull ?? const [];
    if (collections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPaddingMobile,
          ),
          child: Text(
            AppLocalizations.of(context)!.homeSectionCollections,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPaddingMobile,
            ),
            itemCount: collections.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.cardGap),
            itemBuilder: (context, i) {
              final c = collections[i];
              return _CollectionCard(collection: c, colors: colors);
            },
          ),
        ),
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection, required this.colors});

  final Map<String, dynamic> collection;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final coverUrl = collection['cover_image_url'] as String?;
    final title = collection['title'] as String? ?? '';
    final subtitle = collection['subtitle'] as String?;

    return Semantics(
      button: true,
      label: subtitle != null ? '$title, $subtitle' : title,
      onTap: () => context.push('/collection/${collection['slug']}'),
      child: GestureDetector(
        onTap: () => context.push('/collection/${collection['slug']}'),
        child: ExcludeSemantics(
          child: Container(
            width: 260,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              color: colors.backgroundSecondary,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl != null)
                  CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover)
                else
                  Container(
                    color: colors.accentPrimary.withValues(alpha: 0.15),
                  ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB3000000)],
                      stops: [0.3, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
