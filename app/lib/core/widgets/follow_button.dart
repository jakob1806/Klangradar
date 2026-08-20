import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../interests/interests_providers.dart';
import '../theme/app_colors.dart';

/// "Folgen"-Button für Personen/Ensembles/Venues — Nutzeranfrage: "man kann
/// personen noch nicht folgen, da das nicht gespeichert wird". Die
/// Speicherung (user_favorite_persons/_ensembles/_venues via
/// [InterestsService.toggle]) gab es schon für den Interessen-Picker im
/// Profil, nur keinen direkten Button auf der Detailseite selbst — dieses
/// Widget schließt genau diese Lücke, analog zu [FavoriteButton] bei Events.
class FollowButton extends ConsumerWidget {
  const FollowButton({
    required this.category,
    required this.entityId,
    super.key,
  });

  final InterestCategory category;
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interests = ref.watch(userInterestsProvider);
    final l10n = AppLocalizations.of(context)!;
    final colors = context.appColors;

    final idsForCategory = switch (category) {
      InterestCategory.person => interests.valueOrNull?.personIds,
      InterestCategory.ensemble => interests.valueOrNull?.ensembleIds,
      InterestCategory.venue => interests.valueOrNull?.venueIds,
      InterestCategory.genre => null,
    };
    final isFollowing = idsForCategory?.contains(entityId) ?? false;

    Future<void> handleTap() async {
      if (ref.read(currentUserProvider) == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.followSignInPrompt)));
        return;
      }
      await InterestsService.toggle(
        ref,
        category: category,
        id: entityId,
        isSelected: isFollowing,
      );
    }

    final label = isFollowing
        ? l10n.followLabelActive
        : l10n.followLabelInactive;
    return IconButton(
      icon: Icon(
        isFollowing
            ? Icons.bookmark_added_rounded
            : Icons.bookmark_add_outlined,
        color: isFollowing ? colors.accentPrimary : Colors.white,
      ),
      tooltip: label,
      onPressed: handleTap,
    );
  }
}
