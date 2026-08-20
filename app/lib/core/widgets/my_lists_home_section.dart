import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/lists/application/event_lists_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Eigene Konzertlisten mit Titelbild auf der Startseite — Nutzeranfrage:
/// "gleiches Verhalten wie redaktionelle Sammlungen, nur dass das eine vom
/// Nutzer selbst in der App gemacht werden kann". Bewusst dieselbe Kachel-
/// Optik wie [EditorialCollectionsSection], aber eine eigene, nur für den
/// angemeldeten Nutzer sichtbare Sektion statt einer öffentlichen.
class MyListsHomeSection extends ConsumerWidget {
  const MyListsHomeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myListsForHomeProvider);
    final colors = context.appColors;
    final lists = async.valueOrNull ?? const [];
    if (lists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPaddingMobile,
          ),
          child: Text(
            AppLocalizations.of(context)!.homeSectionMyLists,
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
            itemCount: lists.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.cardGap),
            itemBuilder: (context, i) {
              final list = lists[i];
              return _MyListCard(list: list, colors: colors);
            },
          ),
        ),
      ],
    );
  }
}

class _MyListCard extends StatelessWidget {
  const _MyListCard({required this.list, required this.colors});

  final UserEventList list;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final subtitle = l10n.myListsEventCount(list.events.length);

    return Semantics(
      button: true,
      label: '${list.name}, $subtitle',
      onTap: () => context.push('/lists/${list.id}'),
      child: GestureDetector(
        onTap: () => context.push('/lists/${list.id}'),
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
                if (list.coverImageUrl != null)
                  CachedNetworkImage(
                    imageUrl: list.coverImageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: (260 * MediaQuery.devicePixelRatioOf(context)).round(),
                    memCacheHeight: (110 * MediaQuery.devicePixelRatioOf(context)).round(),
                  )
                else
                  Container(color: colors.accentPrimary.withValues(alpha: 0.15)),
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
                        list.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
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
