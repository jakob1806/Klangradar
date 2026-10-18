import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';

enum NotificationPreferenceKey {
  newMatchingEvents('new_matching_events'),
  priceChanges('price_changes'),
  almostSoldOut('almost_sold_out'),
  reminderDayBefore('reminder_day_before'),
  followedEnsembleNewEvent('followed_ensemble_new_event'),
  // E-Mail-Kanal (Migration 20261231000093), default aus.
  emailWeeklyDigest('email_weekly_digest', defaultValue: false),
  emailFollowedNewEvent('email_followed_new_event', defaultValue: false),
  emailEventChanges('email_event_changes', defaultValue: false),
  emailReminderDayBefore('email_reminder_day_before', defaultValue: false);

  const NotificationPreferenceKey(this.column, {this.defaultValue = true});

  final String column;
  final bool defaultValue;
}

class NotificationPreferences {
  const NotificationPreferences(this._values);

  final Map<NotificationPreferenceKey, bool> _values;

  static final defaults = NotificationPreferences({
    for (final key in NotificationPreferenceKey.values) key: key.defaultValue,
  });

  bool operator [](NotificationPreferenceKey key) =>
      _values[key] ?? key.defaultValue;

  bool get newMatchingEvents =>
      this[NotificationPreferenceKey.newMatchingEvents];
  bool get priceChanges => this[NotificationPreferenceKey.priceChanges];
  bool get almostSoldOut => this[NotificationPreferenceKey.almostSoldOut];
  bool get reminderDayBefore =>
      this[NotificationPreferenceKey.reminderDayBefore];
  bool get followedEnsembleNewEvent =>
      this[NotificationPreferenceKey.followedEnsembleNewEvent];

  factory NotificationPreferences.fromRow(Map<String, dynamic> row) {
    return NotificationPreferences({
      for (final key in NotificationPreferenceKey.values)
        key: row[key.column] as bool? ?? key.defaultValue,
    });
  }
}

/// Newsletter = Werbe-Einwilligung aus der Registrierung
/// (profiles.marketing_email_opt_in); der Einwilligungs-Zeitstempel wird per
/// Trigger gesetzt (Migration 20261231000093).
final newsletterOptInProvider = FutureProvider.autoDispose<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final row = await Supabase.instance.client
      .from('profiles')
      .select('marketing_email_opt_in')
      .eq('id', user.id)
      .maybeSingle();
  return row?['marketing_email_opt_in'] as bool? ?? false;
});

/// notification_preferences existiert seit Phase 0 als eigene Tabelle,
/// aber ohne Zeile pro Nutzer (kein Auto-Insert-Trigger wie bei profiles) —
/// vor dem ersten Toggle also einfach noch keine Zeile, daher der
/// Default-Fallback statt .single().
final notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences>((ref) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return NotificationPreferences.defaults;

      final row = await Supabase.instance.client
          .from('notification_preferences')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      return row == null
          ? NotificationPreferences.defaults
          : NotificationPreferences.fromRow(row);
    });

class NotificationPreferencesService {
  const NotificationPreferencesService._();

  static Future<void> setPreference(
    WidgetRef ref, {
    required NotificationPreferenceKey key,
    required bool value,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Upsert statt update — vor dem ersten Toggle gibt es noch keine Zeile;
    // die übrigen Spalten fallen dann korrekt auf ihre eigenen DB-Defaults
    // (default true) zurück statt auf null.
    await Supabase.instance.client.from('notification_preferences').upsert({
      'user_id': user.id,
      key.column: value,
    }, onConflict: 'user_id');
    ref.invalidate(notificationPreferencesProvider);
  }

  static Future<void> setNewsletterOptIn(WidgetRef ref, bool value) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client
        .from('profiles')
        .update({'marketing_email_opt_in': value})
        .eq('id', user.id);
    ref.invalidate(newsletterOptInProvider);
  }
}
