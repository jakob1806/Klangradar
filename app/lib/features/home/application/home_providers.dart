import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/favorites/favorites_providers.dart';
import '../../../core/regions/region_providers.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/time/munich_time.dart';
import '../../follows/application/follows_providers.dart';

// Öffentlich (nicht mehr privat) statt einer eigenen Kopie in
// favorites_screen.dart — die hatte image_urls schlicht vergessen
// (Nutzerfeedback: Favoriten-Miniaturansichten blieben ohne Bild, obwohl
// das Event eins hat). Eine Quelle für die Spaltenliste statt zwei, die
// auseinanderlaufen können.
const homeEventColumns =
    'id, slug, title, subtitle, is_free, remaining_tickets_status, discount_info, start_datetime, venue_detail, image_urls, venues(name), event_genres(genres(slug))';

String _formatDateTime(DateTime d) {
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final now = MunichTime.now();
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
    this.followKind,
    this.followName,
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
  final String? followKind;
  final String? followName;

  factory HomeEventItem.fromRow(Map<String, dynamic> row) {
    final start = MunichTime.tryParse(row['start_datetime'] as String?);
    final venueBase = row['venues']?['name'] as String?;
    final venueDetail = row['venue_detail'] as String?;
    final venueName = venueBase == null
        ? null
        : venueDetail == null || venueDetail.isEmpty
        ? venueBase
        : '$venueBase · $venueDetail';
    final genreSlugs = (row['event_genres'] as List? ?? [])
        .map((g) => g['genres']?['slug'] as String?)
        .whereType<String>();
    final imageUrls = row['image_urls'] as List?;

    // Ticket-Status hat Vorrang vor "Kostenlos"/"Ermäßigt" — ein
    // ausverkauftes Gratis- oder ermäßigtes Event soll das auch als Badge
    // zeigen, nicht die weniger dringliche Info vortäuschen. "Ermäßigt" ist
    // die niedrigste Priorität (Phase A.3-Nachtrag) — nur ein Badge-Slot in
    // der Karte, kein Grund für ein zweites nebenan, wenn eh nur eine
    // dieser Angaben je Karte wirklich relevant ist.
    String? badge;
    switch (row['remaining_tickets_status'] as String?) {
      case 'sold_out':
        badge = 'Ausverkauft';
      case 'few_left':
        badge = 'Fast ausverkauft';
      case 'box_office_only':
        badge = 'Nur Abendkasse';
      default:
        if (row['is_free'] == true) {
          badge = 'Kostenlos';
        } else if ((row['discount_info'] as String?)?.trim().isNotEmpty ==
            true) {
          badge = 'Ermäßigt';
        }
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
      followKind: row['follow_kind'] as String?,
      followName: row['follow_name'] as String?,
    );
  }
}

class HomeData {
  const HomeData({
    required this.hero,
    required this.heute,
    required this.empfehlungen,
    required this.favoriten,
    required this.gefolgt,
    required this.geschmacksTitel,
    required this.geschmack,
    required this.entitySpotlightTitle,
    required this.entitySpotlight,
    required this.entdecken,
    required this.entityNews,
    required this.beliebt,
    required this.kostenlos,
    required this.ausverkauft,
    required this.festival,
    this.festivalName,
  });

  final Map<String, dynamic>? hero;
  final List<HomeEventItem> heute;
  final List<HomeEventItem> empfehlungen;
  final List<HomeEventItem> favoriten;
  final List<HomeEventItem> gefolgt;
  final String? geschmacksTitel;
  final List<HomeEventItem> geschmack;
  final String? entitySpotlightTitle;
  final List<HomeEventItem> entitySpotlight;
  final List<HomeEventItem> entdecken;
  final List<HomeEventItem> entityNews;
  final List<HomeEventItem> beliebt;
  final List<HomeEventItem> kostenlos;
  final List<HomeEventItem> ausverkauft;
  final List<HomeEventItem> festival;
  final String? festivalName;
}

/// Modul-Reihenfolge nach docs/08-home-feed-recommendation-algorithm.md,
/// Abschnitt 3 — bestimmt gleichzeitig die Priorität fürs Cross-Modul-
/// Dedup in [_applyDiversity]: ein Event, das in einem früheren Modul
/// schon gezeigt wurde, verschwindet aus allen späteren. "Dein Ort/
/// Ensemble hat Neuigkeiten" (5.) und "Saisonal/Festival" (7.) sind jetzt
/// Teil der Reihenfolge (Phase B, entity_news_events()/festival_events()).
@visibleForTesting
List<List<HomeEventItem>> orderedModulesForTesting(
  List<HomeEventItem> heute,
  List<HomeEventItem> empfehlungen,
  List<HomeEventItem> entdecken,
  List<HomeEventItem> entityNews,
  List<HomeEventItem> ausverkauft,
  List<HomeEventItem> festival,
  List<HomeEventItem> kostenlos,
  List<HomeEventItem> beliebt,
) => _orderedModules(
  heute,
  empfehlungen,
  entdecken,
  entityNews,
  ausverkauft,
  festival,
  kostenlos,
  beliebt,
);

List<List<HomeEventItem>> _orderedModules(
  List<HomeEventItem> heute,
  List<HomeEventItem> empfehlungen,
  List<HomeEventItem> entdecken,
  List<HomeEventItem> entityNews,
  List<HomeEventItem> ausverkauft,
  List<HomeEventItem> festival,
  List<HomeEventItem> kostenlos,
  List<HomeEventItem> beliebt,
) => [
  heute,
  empfehlungen,
  entdecken,
  entityNews,
  ausverkauft,
  festival,
  kostenlos,
  beliebt,
];

/// Diversitätsregeln 1–3 aus docs/08, Abschnitt 5: kein Event doppelt im
/// selben Feed (modulübergreifend, [seenEventIds] wird beim Aufrufer über
/// alle Module hinweg fortgeschrieben), max. 2 Events desselben Venues pro
/// Modul, max. 1 Event desselben Komponisten pro Modul. Reihenfolge
/// innerhalb eines Moduls bleibt erhalten (schon nach Score/Datum
/// sortiert) — hier wird nur gefiltert, nicht neu sortiert.
@visibleForTesting
List<HomeEventItem> applyDiversityForTesting(
  List<HomeEventItem> items,
  Set<String> seenEventIds,
  Map<String, Set<String>> composerIdsByEvent,
) => _applyDiversity(items, seenEventIds, composerIdsByEvent);

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

/// Komponist:innen pro Event für die Diversitätsregel oben — kommen seit
/// der RPC-Bündelung (Perf-Audit Punkt 1, Nachtrag) direkt aus
/// `home_feed_bundle()`s `composerIdsByEvent`-Feld mit, statt eines eigenen
/// 12. Requests über alle Kandidaten-IDs.
Map<String, Set<String>> _parseComposerIdsByEvent(dynamic json) {
  final map = json as Map<String, dynamic>? ?? const {};
  return map.map(
    (eventId, composerIds) =>
        MapEntry(eventId, (composerIds as List).whereType<String>().toSet()),
  );
}

/// Bleibt beim Tab-Wechsel im Speicher; Pull-to-refresh, Stadtwechsel und
/// Favoriten-/Follow-Änderungen invalidieren den Feed weiterhin gezielt.
final homeDataProvider = FutureProvider<HomeData>((ref) async {
  // Auth-, Like- und Follow-Änderungen invalidieren den Feed unmittelbar.
  // Das ist besonders wichtig beim Login über den Profil-Tab, weil der
  // IndexedStack den bereits aufgebauten Home-Tab sonst im Speicher hält.
  ref.watch(currentUserProvider);
  ref.watch(favoriteIdsProvider);
  ref.watch(myFollowsProvider);
  final region = ref.watch(selectedCityRegionProvider);
  final client = Supabase.instance.client;
  final now = MunichTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));

  // Perf-Audit Punkt 1 (Nachtrag "Homescreen-RPC-Bündeln"): vorher 11
  // parallele Requests (8 RPCs + 3 rohe Table-Selects) plus ein 12. für die
  // Komponisten-Diversität — jetzt ein einziger Roundtrip. Scoring-/
  // Ranking-Logik bleibt unverändert in den bestehenden SQL-Funktionen
  // (hero_event/recommended_events/…), home_feed_bundle() ruft sie nur
  // serverseitig statt clientseitig parallel auf (siehe Migration
  // 20261218000001_home_feed_bundle_rpc.sql für die genauen Parameter/
  // Limits, identisch zu den bisherigen Client-Aufrufen).
  final bundle =
      await client.rpc(
            'home_feed_bundle',
            params: {
              'p_now': now.toIso8601String(),
              'p_today_start': todayStart.toIso8601String(),
              'p_today_end': todayEnd.toIso8601String(),
              if (region != null) 'p_city_id': region.id,
            },
          )
          as Map<String, dynamic>;

  List<HomeEventItem> parseModule(String key) => (bundle[key] as List)
      .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
      .toList();

  final heroRows = bundle['hero'] as List;
  final heute = parseModule('heute');
  final empfehlungen = parseModule('empfehlungen');
  final favoriteCandidates = parseModule('favoriten');
  final followedCandidates = parseModule('gefolgt');
  final entdecken = parseModule('entdecken');
  final entityNews = parseModule('entityNews');
  final ausverkauft = parseModule('ausverkauft');
  final festivalRows = bundle['festival'] as List;
  final festival = parseModule('festival');
  final festivalName = festivalRows.isEmpty
      ? null
      : (festivalRows.first as Map<String, dynamic>)['festival_name']
            as String?;
  final kostenlos = parseModule('kostenlos');
  final beliebt = parseModule('beliebt');
  final composerIdsByEvent = _parseComposerIdsByEvent(
    bundle['composerIdsByEvent'],
  );

  final ordered = _orderedModules(
    heute,
    empfehlungen.take(10).toList(),
    entdecken,
    entityNews,
    ausverkauft,
    festival,
    kostenlos,
    beliebt,
  );

  // Hero vorab als "gesehen" markieren — sonst könnte dasselbe Event direkt
  // darunter im ersten Modul (z.B. "Heute") nochmal auftauchen.
  final heroId = heroRows.isEmpty
      ? null
      : (heroRows.first as Map<String, dynamic>)['id'] as String?;
  final seenEventIds = <String>{if (heroId != null) heroId};
  final favoriten = _applyDiversity(
    favoriteCandidates,
    seenEventIds,
    composerIdsByEvent,
  );
  final gefolgt = _applyDiversity(
    followedCandidates.take(12).toList(),
    seenEventIds,
    composerIdsByEvent,
  );
  final followCounts = <String, int>{};
  for (final item in followedCandidates) {
    if (item.followName != null) {
      followCounts[item.followName!] =
          (followCounts[item.followName!] ?? 0) + 1;
    }
  }
  final spotlightName = followCounts.entries.isEmpty
      ? null
      : (followCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
  final entitySpotlight = _applyDiversity(
    spotlightName == null
        ? []
        : followedCandidates
              .where((item) => item.followName == spotlightName)
              .toList(),
    seenEventIds,
    composerIdsByEvent,
  );
  final spotlightKind = spotlightName == null
      ? null
      : followedCandidates
            .firstWhere((item) => item.followName == spotlightName)
            .followKind;
  final diversified = [
    for (final module in ordered)
      _applyDiversity(module, seenEventIds, composerIdsByEvent),
  ];

  // Ein stabiles, verhaltensbasiertes Spotlight: recommended_events enthält
  // bereits Favoriten-, Follow-, View-, Kalender- und Dismissal-Signale. Aus
  // dem dominanten Genre der hinteren Kandidaten entsteht gelegentlich eine
  // konkrete Geschmacks-Rail statt immer nur des generischen „Für dich“.
  final genreCounts = <EventGenre, int>{};
  for (final item in empfehlungen.skip(7)) {
    genreCounts[item.genre] = (genreCounts[item.genre] ?? 0) + 1;
  }
  final tasteGenre = genreCounts.entries.isEmpty
      ? null
      : (genreCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
  final tasteCandidates = tasteGenre == null
      ? <HomeEventItem>[]
      : empfehlungen.skip(7).where((item) => item.genre == tasteGenre).toList();
  final geschmack = _applyDiversity(
    tasteCandidates,
    seenEventIds,
    composerIdsByEvent,
  );

  // Diversitätsregel 4 (docs/08, Abschnitt 5): protokolliert, was Hero/
  // "Für dich" gerade gezeigt wurde, damit recommended_events()/hero_event()
  // dieselbe Auswahl 7 bzw. 3 Tage lang nicht wiederholen. Fire-and-forget,
  // nur für eingeloggte Nutzer (RLS würde anonyme Inserts ohnehin ablehnen).
  final userId = client.auth.currentUser?.id;
  if (userId != null) {
    final impressions = [
      if (heroId != null)
        {'user_id': userId, 'event_id': heroId, 'module_key': 'hero'},
      for (final item in diversified[1])
        {'user_id': userId, 'event_id': item.id, 'module_key': 'fuer_dich'},
    ];
    if (impressions.isNotEmpty) {
      unawaited(client.from('home_feed_impressions').insert(impressions));
    }
  }

  return HomeData(
    hero: heroRows.isEmpty ? null : heroRows.first as Map<String, dynamic>,
    heute: diversified[0],
    empfehlungen: diversified[1],
    favoriten: favoriten,
    gefolgt: gefolgt,
    geschmacksTitel: tasteGenre == null ? null : _tasteTitle(tasteGenre),
    geschmack: geschmack,
    entitySpotlightTitle: spotlightName == null
        ? null
        : switch (spotlightKind) {
            'venue' => 'Konzerte im $spotlightName',
            'person' => 'Konzerte mit $spotlightName',
            _ => 'Konzerte von $spotlightName',
          },
    entitySpotlight: entitySpotlight,
    entdecken: diversified[2],
    entityNews: diversified[3],
    ausverkauft: diversified[4],
    festival: diversified[5],
    festivalName: festivalName,
    kostenlos: diversified[6],
    beliebt: diversified[7],
  );
});

String _tasteTitle(EventGenre genre) => switch (genre) {
  EventGenre.oper => 'Weil du Oper magst',
  EventGenre.orchester => 'Mehr Symphonik für dich',
  EventGenre.kammermusik => 'Kammermusik nach deinem Geschmack',
  EventGenre.chormusik => 'Chor & Vokalmusik für dich',
  EventGenre.kirchenmusik => 'Orgel & Kirchenmusik für dich',
  _ => 'Mehr von dem, was du magst',
};
