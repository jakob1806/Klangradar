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

List<({NotificationPreferenceKey key, String title, String subtitle})>
_emailRows(AppLocalizations l10n) => [
  (
    key: NotificationPreferenceKey.emailWeeklyDigest,
    title: l10n.notificationEmailDigestTitle,
    subtitle: l10n.notificationEmailDigestSubtitle,
  ),
  (
    key: NotificationPreferenceKey.emailFollowedNewEvent,
    title: l10n.notificationEmailFollowedTitle,
    subtitle: l10n.notificationEmailFollowedSubtitle,
  ),
  (
    key: NotificationPreferenceKey.emailEventChanges,
    title: l10n.notificationEmailChangesTitle,
    subtitle: l10n.notificationEmailChangesSubtitle,
  ),
  (
    key: NotificationPreferenceKey.emailReminderDayBefore,
    title: l10n.notificationEmailReminderTitle,
    subtitle: l10n.notificationEmailReminderSubtitle,
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
        data: (prefs) {
          Widget tile(
            ({NotificationPreferenceKey key, String title, String subtitle})
            row,
          ) => SwitchListTile(
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
          );
          Widget header(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          final newsletter =
              ref.watch(newsletterOptInProvider).valueOrNull ?? false;
          return ListView(
            children: [
              header(l10n.notificationSectionPush),
              for (final row in _rows(l10n)) tile(row),
              header(l10n.notificationSectionEmail),
              for (final row in _emailRows(l10n)) tile(row),
              SwitchListTile(
                title: Text(
                  l10n.notificationNewsletterTitle,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  l10n.notificationNewsletterSubtitle,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                ),
                value: newsletter,
                activeThumbColor: colors.accentPrimary,
                onChanged: (value) {
                  Haptics.light();
                  NotificationPreferencesService.setNewsletterOptIn(ref, value);
                },
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.notificationEmailFooter,
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
