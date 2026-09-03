import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/interests/interests_providers.dart';

/// Kategorisierte Übersicht aller gefolgten Personen/Ensembles/Venues fürs
/// Profil — Nutzeranfrage: "übersichtlich im profil sehen, welchen
/// personen/ensembles oder venues man folgt (kategorisiert)". Bewusst ein
/// eigener Screen statt einer Erweiterung von /interests — die Interessen-
/// Seite ist ein Auswahl-Picker (alle Optionen, an-/abwählbar), hier geht es
/// um eine reine Verwaltungsansicht der bereits gefolgten Entitäten
/// (entfolgen, Benachrichtigungen pro Entität ein-/ausschalten).
class FollowedEntity {
  const FollowedEntity({
    required this.id,
    required this.name,
    required this.slug,
    required this.notifyNewEvents,
  });

  final String id;
  final String name;
  final String slug;
  final bool notifyNewEvents;
}

class MyFollows {
  const MyFollows({
    required this.persons,
    required this.ensembles,
    required this.venues,
  });

  final List<FollowedEntity> persons;
  final List<FollowedEntity> ensembles;
  final List<FollowedEntity> venues;

  bool get isEmpty => persons.isEmpty && ensembles.isEmpty && venues.isEmpty;

  static const empty = MyFollows(persons: [], ensembles: [], venues: []);
}

/// Wird in Home und Profil gebraucht und bleibt deshalb tabübergreifend warm.
final myFollowsProvider = FutureProvider<MyFollows>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return MyFollows.empty;

  final client = Supabase.instance.client;
  final results = await Future.wait([
    client
        .from('user_favorite_persons')
        .select('notify_new_events, persons(id, full_name, slug)')
        .eq('user_id', user.id),
    client
        .from('user_favorite_ensembles')
        .select('notify_new_events, ensembles(id, name, slug)')
        .eq('user_id', user.id),
    client
        .from('user_favorite_venues')
        .select('notify_new_events, venues(id, name, slug)')
        .eq('user_id', user.id),
  ]);

  List<FollowedEntity> mapRows(List rows, String entityKey, String nameKey) =>
      rows
          .map((r) {
            final entity = r[entityKey] as Map<String, dynamic>?;
            if (entity == null) return null;
            return FollowedEntity(
              id: entity['id'] as String,
              name: entity[nameKey] as String,
              slug: entity['slug'] as String,
              notifyNewEvents: r['notify_new_events'] as bool? ?? true,
            );
          })
          .whereType<FollowedEntity>()
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  return MyFollows(
    persons: mapRows(results[0] as List, 'persons', 'full_name'),
    ensembles: mapRows(results[1] as List, 'ensembles', 'name'),
    venues: mapRows(results[2] as List, 'venues', 'name'),
  );
});

class FollowsService {
  const FollowsService._();

  static Future<void> unfollow(
    WidgetRef ref, {
    required InterestCategory category,
    required String id,
  }) async {
    await InterestsService.toggle(
      ref,
      category: category,
      id: id,
      isSelected: true,
    );
    ref.invalidate(myFollowsProvider);
  }

  static Future<void> setNotify(
    WidgetRef ref, {
    required InterestCategory category,
    required String id,
    required bool notify,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    const tableAndColumn = {
      InterestCategory.person: ('user_favorite_persons', 'person_id'),
      InterestCategory.ensemble: ('user_favorite_ensembles', 'ensemble_id'),
      InterestCategory.venue: ('user_favorite_venues', 'venue_id'),
    };
    final (table, column) = tableAndColumn[category]!;
    await Supabase.instance.client
        .from(table)
        .update({'notify_new_events': notify})
        .eq('user_id', user.id)
        .eq(column, id);
    ref.invalidate(myFollowsProvider);
  }
}
