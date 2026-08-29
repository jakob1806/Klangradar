import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../features/follows/application/follows_providers.dart';
import '../auth/auth_providers.dart';
import '../interests/interests_providers.dart';
import '../theme/app_colors.dart';

const Map<InterestCategory, (String table, String column)>
_notifyTableAndColumn = {
  InterestCategory.person: ('user_favorite_persons', 'person_id'),
  InterestCategory.ensemble: ('user_favorite_ensembles', 'ensemble_id'),
  InterestCategory.venue: ('user_favorite_venues', 'venue_id'),
};

typedef _NotifyKey = ({InterestCategory category, String entityId});

/// Ob Benachrichtigungen für eine gefolgte Entität aktiv sind — `null`, wenn
/// der Nutzer der Entität gar nicht folgt (dann gibt es keine Zeile).
final entityNotifyProvider = FutureProvider.autoDispose
    .family<bool?, _NotifyKey>((ref, key) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return null;
      final (table, column) = _notifyTableAndColumn[key.category]!;
      final row = await Supabase.instance.client
          .from(table)
          .select('notify_new_events')
          .eq('user_id', user.id)
          .eq(column, key.entityId)
          .maybeSingle();
      return row?['notify_new_events'] as bool?;
    });

/// Bell-Icon zum Ein-/Ausschalten von Benachrichtigungen für eine gefolgte
/// Person/Ensemble/Venue — Nutzeranfrage: "sie soll explizit auf der
/// Detailseite immer angezeigt werden". Nur sichtbar, solange der Nutzer der
/// Entität folgt (ohne Follow gibt es keine Benachrichtigungs-Zeile, die man
/// umschalten könnte).
class NotifyButton extends ConsumerWidget {
  const NotifyButton({
    required this.category,
    required this.entityId,
    super.key,
  });

  final InterestCategory category;
  final String entityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interests = ref.watch(userInterestsProvider).valueOrNull;
    final idsForCategory = switch (category) {
      InterestCategory.person => interests?.personIds,
      InterestCategory.ensemble => interests?.ensembleIds,
      InterestCategory.venue => interests?.venueIds,
      InterestCategory.genre => null,
    };
    final isFollowing = idsForCategory?.contains(entityId) ?? false;
    if (!isFollowing) return const SizedBox.shrink();

    final key = (category: category, entityId: entityId);
    final notify = ref.watch(entityNotifyProvider(key));
    final l10n = AppLocalizations.of(context)!;
    final colors = context.appColors;
    final isOn = notify.valueOrNull ?? true;

    return IconButton(
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isOn
              ? Icons.notifications_active_rounded
              : Icons.notifications_off_outlined,
          size: 26,
          color: isOn ? colors.accentPrimary : Colors.white,
        ),
      ),
      tooltip: isOn ? l10n.notifyLabelActive : l10n.notifyLabelInactive,
      onPressed: () async {
        await FollowsService.setNotify(
          ref,
          category: category,
          id: entityId,
          notify: !isOn,
        );
        ref.invalidate(entityNotifyProvider(key));
      },
    );
  }
}
