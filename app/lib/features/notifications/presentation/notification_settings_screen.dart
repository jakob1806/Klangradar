import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/haptics.dart';
import '../../../core/notifications/notification_preferences_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';

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
          Widget choice<T>({
            required String title,
            required T value,
            required Map<T, String> options,
            required String column,
          }) => ListTile(
            title: Text(
              title,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: DropdownButton<T>(
              value: options.containsKey(value) ? value : options.keys.first,
              underline: const SizedBox.shrink(),
              items: [
                for (final entry in options.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (selected) {
                if (selected == null) return;
                Haptics.light();
                NotificationPreferencesService.setValue(
                  ref,
                  column,
                  selected as Object,
                );
              },
            ),
          );
          Widget note(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              text,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          );
          final newsletter =
              ref.watch(newsletterOptInProvider).valueOrNull ?? false;
          // Gliederung nach dem Mitteilungs-Konzept (Claude Code, 01.11.2026):
          // Wichtiges sofort, Planung genau eine pro Konzert, Rest im
          // selbst gewählten Wochenbudget.
          return ListView(
            children: [
              header(l10n.notificationSectionImportant),
              note(l10n.notificationAlwaysImmediate),
              tile((
                key: NotificationPreferenceKey.pushChanges,
                title: l10n.notificationChangesTitle,
                subtitle: l10n.notificationChangesSubtitle,
              )),
              header(l10n.notificationSectionMyConcerts),
              tile((
                key: NotificationPreferenceKey.reminderDayBefore,
                title: l10n.notificationConcertDayTitle,
                subtitle: l10n.notificationConcertDaySubtitle,
              )),
              tile((
                key: NotificationPreferenceKey.almostSoldOut,
                title: l10n.notificationAlmostSoldOutTitle,
                subtitle: l10n.notificationAlmostSoldOutSubtitle,
              )),
              tile((
                key: NotificationPreferenceKey.pushHowWasIt,
                title: l10n.notificationHowWasItTitle,
                subtitle: l10n.notificationHowWasItSubtitle,
              )),
              header(l10n.notificationSectionDiscover),
              choice<String>(
                title: l10n.notificationNewFollowedTitle,
                value: prefs.newFollowed,
                column: 'push_new_followed',
                options: {
                  'off': l10n.notificationFrequencyOff,
                  'weekly': l10n.notificationFrequencyWeekly,
                  'daily': l10n.notificationFrequencyDaily,
                  'twice_daily': l10n.notificationFrequencyTwiceDaily,
                },
              ),
              tile((
                key: NotificationPreferenceKey.pushWeeklyPick,
                title: l10n.notificationWeeklyPickTitle,
                subtitle: l10n.notificationWeeklyPickSubtitle,
              )),
              header(l10n.notificationSectionFriends),
              choice<String>(
                title: l10n.notificationFriendsTitle,
                value: prefs.friends,
                column: 'push_friends',
                options: {
                  'direct': l10n.notificationFriendsDirect,
                  'daily': l10n.notificationFriendsDaily,
                  'off': l10n.notificationFrequencyOff,
                },
              ),
              tile((
                key: NotificationPreferenceKey.pushFriendActivity,
                title: l10n.notificationFriendActivityTitle,
                subtitle: l10n.notificationFriendActivitySubtitle,
              )),
              header(l10n.notificationSectionLimit),
              choice<int>(
                title: l10n.notificationWeeklyLimitTitle,
                value: prefs.weeklyLimit,
                column: 'push_weekly_limit',
                options: {
                  for (final n in const [5, 10, 15, 20, 30])
                    n: l10n.notificationWeeklyLimitValue(n),
                },
              ),
              note(l10n.notificationWeeklyLimitFooter),
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
