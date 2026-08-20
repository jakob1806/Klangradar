import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../home/application/home_providers.dart';

/// Nutzeranfrage: "wenn ich eine Liste unter 'Meine Listen' erstellen will,
/// fehlt die Funktion, ausgewählte Veranstaltungen zu speichern" — "Meine
/// Listen" war in Flutter bisher nur ein "Kommt bald"-Stub
/// (profile_screen.dart), obwohl favorite_lists/favorite_list_items schon
/// länger existieren und iOS-nativ dieselben Tabellen längst vollständig
/// nutzt (UserRepository.eventLists/createEventList/…). Dieselbe
/// Tabellenstruktur, jetzt auch in Flutter angebunden.
class UserEventList {
  const UserEventList({
    required this.id,
    required this.name,
    required this.events,
    this.coverImageUrl,
  });

  final String id;
  final String name;
  final List<HomeEventItem> events;
  final String? coverImageUrl;
}

final myEventListsProvider = FutureProvider.autoDispose<List<UserEventList>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final rows = await Supabase.instance.client
      .from('favorite_lists')
      .select(
        'id, name, created_at, cover_image_url, '
        'favorite_list_items(events($homeEventColumns))',
      )
      .eq('user_id', user.id)
      .order('created_at', ascending: false);

  return (rows as List).map((r) {
    final events =
        (r['favorite_list_items'] as List? ?? [])
            .map((item) => item['events'] as Map<String, dynamic>?)
            .whereType<Map<String, dynamic>>()
            .map(HomeEventItem.fromRow)
            .toList()
          ..sort((a, b) {
            final aStart = a.startDateTime ?? DateTime(9999);
            final bStart = b.startDateTime ?? DateTime(9999);
            return aStart.compareTo(bStart);
          });
    return UserEventList(
      id: r['id'] as String,
      name: r['name'] as String,
      events: events,
      coverImageUrl: r['cover_image_url'] as String?,
    );
  }).toList();
});

/// Nutzeranfrage: "Listen sollen auch auf der Homepage angezeigt werden
/// können, gleiches Verhalten wie redaktionelle Sammlungen" — nur Listen mit
/// gesetztem Titelbild UND mindestens einem noch bevorstehenden Event
/// erscheinen dort (dieselbe Ausblend-Logik wie
/// [editorialCollectionsProvider] für abgelaufene Sammlungen).
final myListsForHomeProvider = FutureProvider.autoDispose<List<UserEventList>>((
  ref,
) async {
  final lists = await ref.watch(myEventListsProvider.future);
  final now = DateTime.now();
  return lists
      .where(
        (l) =>
            l.coverImageUrl != null &&
            l.events.any(
              (e) => e.startDateTime != null && e.startDateTime!.isAfter(now),
            ),
      )
      .toList();
});

class EventListsService {
  const EventListsService._();

  static Future<String?> create(WidgetRef ref, String name) async {
    final user = Supabase.instance.client.auth.currentUser;
    final cleanName = name.trim();
    if (user == null || cleanName.isEmpty) return null;

    final row = await Supabase.instance.client
        .from('favorite_lists')
        .insert({'user_id': user.id, 'name': cleanName})
        .select('id')
        .single();
    ref.invalidate(myEventListsProvider);
    return row['id'] as String;
  }

  static Future<void> rename(WidgetRef ref, String listId, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    await Supabase.instance.client
        .from('favorite_lists')
        .update({'name': cleanName})
        .eq('id', listId);
    ref.invalidate(myEventListsProvider);
  }

  /// Titelbild für die Home-Anzeige (Nutzeranfrage: "gleiches Verhalten wie
  /// redaktionelle Sammlungen, ... dass ihnen auch ein übergeordnetes Bild
  /// zugeordnet werden kann") — Pfad `<user_id>/<list_id>.jpg`, analog zu
  /// ProfileAvatarEditor.
  static Future<void> setCoverImage(
    WidgetRef ref,
    String listId,
    Uint8List imageBytes,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final path = '${user.id}/$listId.jpg';
    await Supabase.instance.client.storage
        .from('list-covers')
        .uploadBinary(
          path,
          imageBytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
            cacheControl: '3600',
          ),
        );
    final publicUrl = Supabase.instance.client.storage
        .from('list-covers')
        .getPublicUrl(path);
    final versionedUrl =
        '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    await Supabase.instance.client
        .from('favorite_lists')
        .update({'cover_image_url': versionedUrl})
        .eq('id', listId);
    ref.invalidate(myEventListsProvider);
  }

  static Future<void> removeCoverImage(WidgetRef ref, String listId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await Supabase.instance.client.storage.from('list-covers').remove([
      '${user.id}/$listId.jpg',
    ]);
    await Supabase.instance.client
        .from('favorite_lists')
        .update({'cover_image_url': null})
        .eq('id', listId);
    ref.invalidate(myEventListsProvider);
  }

  static Future<void> delete(WidgetRef ref, String listId) async {
    await Supabase.instance.client
        .from('favorite_lists')
        .delete()
        .eq('id', listId);
    ref.invalidate(myEventListsProvider);
  }

  /// Setzt den Event-Bestand einer Liste komplett auf [selected] — Diff
  /// gegen [previous] statt "alles löschen und neu einfügen", damit
  /// added_at bei unverändert bleibenden Events erhalten bleibt.
  static Future<void> replaceEvents(
    WidgetRef ref, {
    required String listId,
    required Set<String> selected,
    required Set<String> previous,
  }) async {
    final toAdd = selected.difference(previous);
    final toRemove = previous.difference(selected);

    if (toAdd.isNotEmpty) {
      await Supabase.instance.client.from('favorite_list_items').insert([
        for (final eventId in toAdd) {'list_id': listId, 'event_id': eventId},
      ]);
    }
    for (final eventId in toRemove) {
      await Supabase.instance.client
          .from('favorite_list_items')
          .delete()
          .eq('list_id', listId)
          .eq('event_id', eventId);
    }
    ref.invalidate(myEventListsProvider);
  }
}
