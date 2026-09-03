import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/haptics.dart';
import '../../../core/notifications/notification_preferences_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';

List<({NotificationPreferenceKey key, String title, String subtitle})> _rows(
  AppLocalizations l10n,
) => [
  (
    key: NotificationPreferenceKey.newMatchingEvents,
    title: l10n.notificationNewMatchingTitle,
    subtitle: l10n.notificationNewMatchingSubtitle,
  ),
  (
    key: NotificationPreferenceKey.priceChanges,
    title: l10n.notificationPriceChangesTitle,
    subtitle: l10n.notificationPriceChangesSubtitle,
  ),
  (
    key: NotificationPreferenceKey.almostSoldOut,
    title: l10n.notificationAlmostSoldOutTitle,
    subtitle: l10n.notificationAlmostSoldOutSubtitle,
  ),
  (
    key: NotificationPreferenceKey.reminderDayBefore,
    title: l10n.notificationReminderTitle,
    subtitle: l10n.notificationReminderSubtitle,
  ),
  (
    key: NotificationPreferenceKey.followedEnsembleNewEvent,
    title: l10n.notificationFollowedEnsembleTitle,
    subtitle: l10n.notificationFollowedEnsembleSubtitle,
  ),
];

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final user = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context)!;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.notificationsAppBarTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l10n.notificationsSignInPrompt,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        ),
      );
    }

    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsAppBarTitle)),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            l10n.errorLoadingGeneric(e.toString()),
            style: TextStyle(color: colors.error),
          ),
        ),
        data: (prefs) => ListView(
          children: [
            for (final row in _rows(l10n))
              SwitchListTile(
                title: Text(
                  row.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  row.subtitle,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                ),
                value: prefs[row.key],
                activeThumbColor: colors.accentPrimary,
                onChanged: (value) {
                  // Erinnerung/Benachrichtigung aktivieren = Bestätigung
                  // (Nutzer-Vorgabe); übrige Einstellungs-Toggles nur leicht.
                  if (row.key == NotificationPreferenceKey.reminderDayBefore &&
                      value) {
                    Haptics.confirm();
                  } else {
                    Haptics.light();
                  }
                  NotificationPreferencesService.setPreference(
                    ref,
                    key: row.key,
                    value: value,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
