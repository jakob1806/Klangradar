import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/interests/interests_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/follows_providers.dart';

class MyFollowsScreen extends ConsumerWidget {
  const MyFollowsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final user = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context)!;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.myFollowsAppBarTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l10n.myFollowsSignInPrompt,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        ),
      );
    }

    final followsAsync = ref.watch(myFollowsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myFollowsAppBarTitle)),
      body: followsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            l10n.errorLoadingGeneric(e.toString()),
            style: TextStyle(color: colors.error),
          ),
        ),
        data: (follows) {
          if (follows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  l10n.myFollowsEmptyState,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            children: [
              if (follows.persons.isNotEmpty)
                _FollowSection(
                  title: l10n.myFollowsSectionPersons,
                  category: InterestCategory.person,
                  entities: follows.persons,
                  routePrefix: '/person',
                  colors: colors,
                  l10n: l10n,
                ),
              if (follows.ensembles.isNotEmpty)
                _FollowSection(
                  title: l10n.myFollowsSectionEnsembles,
                  category: InterestCategory.ensemble,
                  entities: follows.ensembles,
                  routePrefix: '/ensemble',
                  colors: colors,
                  l10n: l10n,
                ),
              if (follows.venues.isNotEmpty)
                _FollowSection(
                  title: l10n.myFollowsSectionVenues,
                  category: InterestCategory.venue,
                  entities: follows.venues,
                  routePrefix: '/venue',
                  colors: colors,
                  l10n: l10n,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FollowSection extends StatelessWidget {
  const _FollowSection({
    required this.title,
    required this.category,
    required this.entities,
    required this.routePrefix,
    required this.colors,
    required this.l10n,
  });

  final String title;
  final InterestCategory category;
  final List<FollowedEntity> entities;
  final String routePrefix;
  final AppColorsExtension colors;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPaddingMobile,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final entity in entities)
            _FollowRow(
              entity: entity,
              category: category,
              routePrefix: routePrefix,
              colors: colors,
              l10n: l10n,
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _FollowRow extends ConsumerWidget {
  const _FollowRow({
    required this.entity,
    required this.category,
    required this.routePrefix,
    required this.colors,
    required this.l10n,
  });

  final FollowedEntity entity;
  final InterestCategory category;
  final String routePrefix;
  final AppColorsExtension colors;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push('$routePrefix/${entity.slug}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.separator)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entity.name,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
              ),
            ),
            IconButton(
              icon: Icon(
                entity.notifyNewEvents
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_outlined,
                size: 20,
                color: entity.notifyNewEvents
                    ? colors.accentPrimary
                    : colors.textTertiary,
              ),
              tooltip: entity.notifyNewEvents
                  ? l10n.myFollowsNotifyTooltipOn
                  : l10n.myFollowsNotifyTooltipOff,
              onPressed: () => FollowsService.setNotify(
                ref,
                category: category,
                id: entity.id,
                notify: !entity.notifyNewEvents,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.bookmark_remove_outlined,
                size: 20,
                color: colors.textTertiary,
              ),
              tooltip: l10n.myFollowsUnfollowTooltip,
              onPressed: () => FollowsService.unfollow(
                ref,
                category: category,
                id: entity.id,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
