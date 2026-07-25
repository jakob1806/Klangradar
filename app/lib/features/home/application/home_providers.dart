import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/genre_artwork.dart';

const _homeEventColumns =
    'id, slug, title, subtitle, is_free, remaining_tickets_status, start_datetime, image_urls, venues(name), event_genres(genres(slug))';

String _formatDateTime(DateTime d) {
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final now = DateTime.now();
  final isToday =
      d.year == now.year && d.month == now.month && d.day == now.day;
  if (isToday) return 'Heute · $time';
  return '${d.day}.${d.month}. · $time';
}

class HomeEventItem {
  const HomeEventItem({
    required this.id,
    required this.slug,
    required this.title,
    required this.venueAndTime,
    required this.genre,
    required this.startDateTime,
    this.venueId,
    this.badge,
    this.imageUrl,
  });

  final String id;
  final String slug;
  final String title;
  final String venueAndTime;
  final EventGenre genre;
  final DateTime? startDateTime;
  final String? venueId;
  final String? badge;
  final String? imageUrl;

  factory HomeEventItem.fromRow(Map<String, dynamic> row) {
    final start = DateTime.tryParse(row['start_datetime'] as String? ?? '');
    final venueName = row['venues']?['name'] as String?;
    final genreSlugs = (row['event_genres'] as List? ?? [])
        .map((g) => g['genres']?['slug'] as String?)
        .whereType<String>();
    final imageUrls = row['image_urls'] as List?;

    String? badge;
    if (row['is_free'] == true) {
      badge = 'Kostenlos';
    } else if (row['remaining_tickets_status'] == 'few_left') {
      badge = 'Fast ausverkauft';
    }

    return HomeEventItem(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String? ?? '',
      venueAndTime: [
        venueName,
        start != null ? _formatDateTime(start) : null,
      ].whereType<String>().join(' · '),
      genre: EventGenre.fromSlug(genreSlugs.isEmpty ? null : genreSlugs.first),
      startDateTime: start,
      venueId: row['venue_id'] as String?,
      badge: badge,
      imageUrl: (imageUrls != null && imageUrls.isNotEmpty)
          ? imageUrls.first as String?
          : null,
    );
  }
}

class HomeData {
  const HomeData({
    required this.hero,
    required this.heute,
    required this.empfehlungen,
    required this.entdecken,
    required this.beliebt,
    required this.kostenlos,
    required this.ausverkauft,
  });

  final Map<String, dynamic>? hero;
  final List<HomeEventItem> heute;
  final List<HomeEventItem> empfehlungen;
  final List<HomeEventItem> entdecken;
  final List<HomeEventItem> beliebt;
  final List<HomeEventItem> kostenlos;
  final List<HomeEventItem> ausverkauft;
}

/// Modul-Reihenfolge nach docs/08-home-feed-recommendation-algorithm.md,
/// Abschnitt 3 — bestimmt gleichzeitig die Priorität fürs Cross-Modul-
/// Dedup in [_applyDiversity]: ein Event, das in einem früheren Modul
/// schon gezeigt wurde, verschwindet aus allen späteren.
/// "Dein Ort hat Neuigkeiten" und "Saisonal/Festival" (ebenfalls in
/// Abschnitt 3 vorgesehen) fehlen hier bewusst — beide brauchen laut
/// Abschnitt 9 noch nicht existierendes Schema (Phase B), nicht Teil
/// dieser ersten Umsetzung.
List<List<HomeEventItem>> _orderedModules(
  List<HomeEventItem> heute,
  List<HomeEventItem> empfehlungen,
  List<HomeEventItem> entdecken,
  List<HomeEventItem> ausverkauft,
  List<HomeEventItem> kostenlos,
  List<HomeEventItem> beliebt,
) => [heute, empfehlungen, entdecken, ausverkauft, kostenlos, beliebt];

/// Diversitätsregeln 1–3 aus docs/08, Abschnitt 5: kein Event doppelt im
/// selben Feed (modulübergreifend, [seenEventIds] wird beim Aufrufer über
/// alle Module hinweg fortgeschrieben), max. 2 Events desselben Venues pro
/// Modul, max. 1 Event desselben Komponisten pro Modul. Reihenfolge
/// innerhalb eines Moduls bleibt erhalten (schon nach Score/Datum
/// sortiert) — hier wird nur gefiltert, nicht neu sortiert.
List<HomeEventItem> _applyDiversity(
  List<HomeEventItem> items,
  Set<String> seenEventIds,
  Map<String, Set<String>> composerIdsByEvent,
) {
  final venueCounts = <String, int>{};
  final usedComposerIds = <String>{};
  final result = <HomeEventItem>[];

  for (final item in items) {
    if (seenEventIds.contains(item.id)) continue;

    final venueId = item.venueId;
    if (venueId != null && (venueCounts[venueId] ?? 0) >= 2) continue;

    final composerIds = composerIdsByEvent[item.id] ?? const <String>{};
    if (composerIds.any(usedComposerIds.contains)) continue;

    result.add(item);
    seenEventIds.add(item.id);
    if (venueId != null) venueCounts[venueId] = (venueCounts[venueId] ?? 0) + 1;
    usedComposerIds.addAll(composerIds);
  }

  return result;
}

/// Komponist:innen pro Event für die Diversitätsregel oben — ein einzelner
/// gezielter Nachschlag über genau die schon geladenen Kandidaten-IDs
/// (keine zusätzliche Abfrage pro Event/Modul).
Future<Map<String, Set<String>>> _loadComposerIdsByEvent(
  SupabaseClient client,
  Iterable<String> eventIds,
) async {
  if (eventIds.isEmpty) return {};
  final rows = await client
      .from('event_works')
      .select('event_id, works(composer_id)')
      .inFilter('event_id', eventIds.toList());

  final result = <String, Set<String>>{};
  for (final row in rows as List) {
    final eventId = row['event_id'] as String?;
    final composerId = row['works']?['composer_id'] as String?;
    if (eventId == null || composerId == null) continue;
    result.putIfAbsent(eventId, () => {}).add(composerId);
  }
  return result;
}

final homeDataProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final client = Supabase.instance.client;
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));
  final nowIso = now.toIso8601String();

  final results = await Future.wait<dynamic>([
    client
        .from('events')
        .select(_homeEventColumns)
        .eq('status', 'scheduled')
        .gte('start_datetime', nowIso)
        .order('start_datetime')
        .limit(1),
    client
        .from('events')
        .select(_homeEventColumns)
        .eq('status', 'scheduled')
        .gte('start_datetime', todayStart.toIso8601String())
        .lt('start_datetime', todayEnd.toIso8601String())
        .order('start_datetime'),
    // Regelbasierte Empfehlungen (docs/08-home-feed-recommendation-
    // algorithm.md, Abschnitt 4.1/0) — degradiert für anonyme/interesselose
    // Nutzer serverseitig automatisch zu Popularität + zeitlicher Nähe,
    // kein Sonderfall hier im Client nötig.
    client.rpc('recommended_events', params: {'p_result_limit': 10}),
    // "Entdecken" (docs/08, Abschnitt 4.3): semantische Ähnlichkeit zu
    // zuletzt favorisierten/angesehenen Events statt Geschmacks-Regeln —
    // liefert ohne Login oder ohne jede Historie bewusst eine leere Liste
    // (RPC-seitig, kein Sonderfall hier nötig).
    client.rpc('discovery_events', params: {'p_result_limit': 10}),
    client
        .from('events')
        .select(_homeEventColumns)
        .eq('status', 'scheduled')
        .eq('remaining_tickets_status', 'few_left')
        .gte('start_datetime', nowIso)
        .order('start_datetime')
        .limit(10),
    client
        .from('events')
        .select(_homeEventColumns)
        .eq('status', 'scheduled')
        .eq('is_free', true)
        .gte('start_datetime', nowIso)
        .order('start_datetime')
        .limit(10),
    client.rpc('popular_events', params: {'p_result_limit': 10}),
  ]);

  final heroRows = results[0] as List;
  final heute = (results[1] as List)
      .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
      .toList();
  final empfehlungen = (results[2] as List)
      .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
      .toList();
  final entdecken = (results[3] as List)
      .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
      .toList();
  final ausverkauft = (results[4] as List)
      .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
      .toList();
  final kostenlos = (results[5] as List)
      .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
      .toList();
  final beliebt = (results[6] as List)
      .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
      .toList();

  final ordered = _orderedModules(
    heute,
    empfehlungen,
    entdecken,
    ausverkauft,
    kostenlos,
    beliebt,
  );
  final allIds = ordered.expand((m) => m.map((e) => e.id));
  final composerIdsByEvent = await _loadComposerIdsByEvent(client, allIds);

  // Hero vorab als "gesehen" markieren — sonst könnte dasselbe Event direkt
  // darunter im ersten Modul (z.B. "Heute") nochmal auftauchen.
  final heroId = heroRows.isEmpty
      ? null
      : (heroRows.first as Map<String, dynamic>)['id'] as String?;
  final seenEventIds = <String>{if (heroId != null) heroId};
  final diversified = [
    for (final module in ordered)
      _applyDiversity(module, seenEventIds, composerIdsByEvent),
  ];

  return HomeData(
    hero: heroRows.isEmpty ? null : heroRows.first as Map<String, dynamic>,
    heute: diversified[0],
    empfehlungen: diversified[1],
    entdecken: diversified[2],
    ausverkauft: diversified[3],
    kostenlos: diversified[4],
    beliebt: diversified[5],
  );
});
