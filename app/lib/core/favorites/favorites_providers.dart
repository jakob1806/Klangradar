import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';

/// IDs der vom aktuellen Nutzer favorisierten Events. Ein einzelner Set-Read
/// statt einer Einzelabfrage pro Karte — wird nach jedem Toggle invalidiert.
final favoriteIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return {};

  final rows = await Supabase.instance.client
      .from('favorites')
      .select('event_id')
      .eq('user_id', user.id);
  return (rows as List).map((r) => r['event_id'] as String).toSet();
});

enum FavoriteStatus {
  interested('interested'),
  attending('attending');

  const FavoriteStatus(this.value);

  final String value;

  static FavoriteStatus fromValue(String? value) => value == 'attending'
      ? FavoriteStatus.attending
      : FavoriteStatus.interested;
}

class FavoritesService {
  const FavoritesService._();

  static Future<void> toggle(
    WidgetRef ref, {
    required String eventId,
    required bool isFavorited,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (isFavorited) {
      await Supabase.instance.client
          .from('favorites')
          .delete()
          .eq('user_id', user.id)
          .eq('event_id', eventId);
    } else {
      await Supabase.instance.client.from('favorites').insert({
        'user_id': user.id,
        'event_id': eventId,
      });
    }
    ref.invalidate(favoriteIdsProvider);
  }

  /// "Interessiert" ↔ "Besuche ich" umschalten (Nutzerwunsch: "als
  /// 'interessiert' oder 'besuche ich' markieren") — unabhängig vom
  /// Favorisieren selbst, das bleibt weiterhin ein einfaches Herz-Tippen.
  static Future<void> setStatus(
    WidgetRef ref, {
    required String eventId,
    required FavoriteStatus status,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await Supabase.instance.client
        .from('favorites')
        .update({'status': status.value})
        .eq('user_id', user.id)
        .eq('event_id', eventId);
    ref.invalidate(favoriteIdsProvider);
  }
}
