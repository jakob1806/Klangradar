import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';

class InterestOption {
  const InterestOption({required this.id, required this.label});

  final String id;
  final String label;
}

final genreOptionsProvider = FutureProvider.autoDispose<List<InterestOption>>((
  ref,
) async {
  final rows = await Supabase.instance.client
      .from('genres')
      .select('id, label_de')
      .order('sort_order', ascending: true);
  return (rows as List)
      .map(
        (r) => InterestOption(
          id: r['id'] as String,
          label: r['label_de'] as String,
        ),
      )
      .toList();
});

final composerOptionsProvider =
    FutureProvider.autoDispose<List<InterestOption>>((ref) async {
      final rows = await Supabase.instance.client
          .from('persons')
          .select('id, full_name')
          .contains('roles', ['komponist'])
          .order('full_name', ascending: true);
      return (rows as List)
          .map(
            (r) => InterestOption(
              id: r['id'] as String,
              label: r['full_name'] as String,
            ),
          )
          .toList();
    });

final ensembleOptionsProvider =
    FutureProvider.autoDispose<List<InterestOption>>((ref) async {
      final rows = await Supabase.instance.client
          .from('ensembles')
          .select('id, name')
          .eq('is_resolution_placeholder', false)
          .eq('is_family_root', false)
          .order('name', ascending: true);
      return (rows as List)
          .map(
            (r) => InterestOption(
              id: r['id'] as String,
              label: r['name'] as String,
            ),
          )
          .toList();
    });

final venueOptionsProvider = FutureProvider.autoDispose<List<InterestOption>>((
  ref,
) async {
  final rows = await Supabase.instance.client
      .from('venues')
      .select('id, name')
      .order('name', ascending: true);
  return (rows as List)
      .map(
        (r) =>
            InterestOption(id: r['id'] as String, label: r['name'] as String),
      )
      .toList();
});

class UserInterests {
  const UserInterests({
    required this.genreIds,
    required this.personIds,
    required this.ensembleIds,
    required this.venueIds,
  });

  final Set<String> genreIds;
  final Set<String> personIds;
  final Set<String> ensembleIds;
  final Set<String> venueIds;

  static const empty = UserInterests(
    genreIds: {},
    personIds: {},
    ensembleIds: {},
    venueIds: {},
  );
}

final userInterestsProvider = FutureProvider.autoDispose<UserInterests>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return UserInterests.empty;

  final client = Supabase.instance.client;
  final results = await Future.wait([
    client
        .from('profile_interest_genres')
        .select('genre_id')
        .eq('user_id', user.id),
    // user_favorite_persons/_ensembles/_venues statt eigener
    // profile_interest_*-Tabellen — die existierten schon seit Phase 0
    // für genau dieses Feature (siehe RLS-Policy-Namen "Nutzer verwaltet
    // eigene Interessen"), nur profile_interest_genres hat dort keine
    // Entsprechung.
    client
        .from('user_favorite_persons')
        .select('person_id')
        .eq('user_id', user.id),
    client
        .from('user_favorite_ensembles')
        .select('ensemble_id')
        .eq('user_id', user.id),
    client
        .from('user_favorite_venues')
        .select('venue_id')
        .eq('user_id', user.id),
  ]);

  return UserInterests(
    genreIds: (results[0] as List).map((r) => r['genre_id'] as String).toSet(),
    personIds: (results[1] as List)
        .map((r) => r['person_id'] as String)
        .toSet(),
    ensembleIds: (results[2] as List)
        .map((r) => r['ensemble_id'] as String)
        .toSet(),
    venueIds: (results[3] as List).map((r) => r['venue_id'] as String).toSet(),
  );
});

enum InterestCategory { genre, person, ensemble, venue }

class InterestsService {
  const InterestsService._();

  static const Map<InterestCategory, (String table, String column)>
  _tableAndColumn = {
    InterestCategory.genre: ('profile_interest_genres', 'genre_id'),
    InterestCategory.person: ('user_favorite_persons', 'person_id'),
    InterestCategory.ensemble: ('user_favorite_ensembles', 'ensemble_id'),
    InterestCategory.venue: ('user_favorite_venues', 'venue_id'),
  };

  static Future<void> toggle(
    WidgetRef ref, {
    required InterestCategory category,
    required String id,
    required bool isSelected,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final (table, column) = _tableAndColumn[category]!;
    if (isSelected) {
      await Supabase.instance.client
          .from(table)
          .delete()
          .eq('user_id', user.id)
          .eq(column, id);
    } else {
      await Supabase.instance.client.from(table).insert({
        'user_id': user.id,
        column: id,
      });
    }
    ref.invalidate(userInterestsProvider);
  }
}
