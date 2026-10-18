import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/home/application/home_providers.dart';
import '../time/munich_time.dart';

/// Aktive, bezahlte Promotionen (Parität zu iOS `PromotedEventsStore`):
/// 1. [ids]: [EventCard] zeigt dafür oben links ein dezentes „Anzeige“-Label
///    (Werbung muss als solche erkennbar sein).
/// 2. Platzierung: erste Karte in „Empfehlungen“ (`local_spotlight`), in
///    „Entdecken“ (`featured`) und vorn bei „Heute“ (`standard`). Das
///    Titelbild (`homepage_feature`) wählt bereits die `hero_event`-RPC.
///    Mehrere Buchungen derselben Platzierung rotieren täglich.
class PromotedEvents {
  const PromotedEvents({required this.ids, required this.byPlacement});

  static const empty = PromotedEvents(ids: {}, byPlacement: {});

  final Set<String> ids;
  final Map<String, List<({HomeEventItem item, String? cityId})>> byPlacement;

  /// Beworbene Events einer Platzierung für die gewählte Stadt, täglich rotiert.
  List<HomeEventItem> eventsFor(
    String placement, {
    String? regionId,
    DateTime? now,
  }) {
    final today = now ?? MunichTime.now();
    final candidates = (byPlacement[placement] ?? const [])
        .where(
          (e) => regionId == null || e.cityId == null || e.cityId == regionId,
        )
        .where(
          (e) =>
              e.item.startDateTime == null ||
              e.item.startDateTime!.isAfter(today),
        )
        .map((e) => e.item)
        .toList();
    if (candidates.length < 2) return candidates;
    final day = today.difference(DateTime(2000)).inDays;
    final offset = day % candidates.length;
    return [...candidates.sublist(offset), ...candidates.sublist(0, offset)];
  }

  /// Setzt beworbene Events an den Anfang einer Liste (ohne Duplikate).
  List<HomeEventItem> boosting(
    List<HomeEventItem> list,
    String placement, {
    String? regionId,
    int maxPromoted = 1,
    bool Function(HomeEventItem)? where,
    DateTime? now,
  }) {
    final promoted = eventsFor(
      placement,
      regionId: regionId,
      now: now,
    ).where(where ?? (_) => true).take(maxPromoted).toList();
    if (promoted.isEmpty) return list;
    final promotedIds = promoted.map((e) => e.id).toSet();
    return [...promoted, ...list.where((e) => !promotedIds.contains(e.id))];
  }
}

final promotedEventsProvider = FutureProvider<PromotedEvents>((ref) async {
  final client = Supabase.instance.client;
  try {
    final rows = await client.rpc('active_event_promotions') as List<dynamic>;
    final placementIds = <String, List<String>>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final id = row['event_id'] as String?;
      final placement = row['placement'] as String?;
      if (id == null || placement == null) continue;
      placementIds.putIfAbsent(placement, () => []).add(id);
    }
    final allIds = placementIds.values.expand((ids) => ids).toSet();
    if (allIds.isEmpty) return PromotedEvents.empty;

    final columns = homeEventColumns.replaceFirst(
      'venues(name)',
      'venues(name, city_id)',
    );
    final eventRows = await client
        .from('events')
        .select(columns)
        .inFilter('id', allIds.toList());
    final byId = <String, ({HomeEventItem item, String? cityId})>{};
    for (final row in eventRows) {
      byId[row['id'] as String] = (
        item: HomeEventItem.fromRow(row),
        cityId: (row['venues'] as Map<String, dynamic>?)?['city_id'] as String?,
      );
    }
    return PromotedEvents(
      ids: allIds,
      byPlacement: placementIds.map(
        (placement, ids) => MapEntry(
          placement,
          ids
              .map((id) => byId[id])
              .whereType<({HomeEventItem item, String? cityId})>()
              .toList(),
        ),
      ),
    );
  } catch (_) {
    // Ohne Daten gibt es schlicht keine Platzierung.
    return PromotedEvents.empty;
  }
});
