import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/regions/region_providers.dart';
import '../../../core/time/munich_time.dart';
import '../../home/application/home_providers.dart';

/// Schlüssel für [monthEventsProvider] — Jahr+Monat statt eines konkreten
/// Tages, damit ein Monatswechsel im Kalender genau eine Query auslöst statt
/// einer pro sichtbarem Tag.
class MonthKey {
  const MonthKey(this.year, this.month);

  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      other is MonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

const _calendarEventColumns =
    'id, slug, title, subtitle, is_free, remaining_tickets_status, discount_info, start_datetime, image_urls, venues(name), event_genres(genres(slug))';

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// Events eines Monats, gruppiert nach Kalendertag — Basis sowohl für die
/// Punkt-Marker im Monatsraster als auch für die Agenda-Liste darunter.
final monthEventsProvider = FutureProvider.autoDispose
    .family<Map<DateTime, List<HomeEventItem>>, MonthKey>((ref, key) async {
      // .toUtc() vor dem Serialisieren: DateTime(y,m,d) ist ein lokaler
      // Zeitpunkt, aber start_datetime ist eine timestamptz-Spalte — ohne
      // .toUtc() serialisiert toIso8601String() ohne Offset/"Z", und
      // PostgREST interpretiert das dann in der Session-Zeitzone der DB
      // (UTC), nicht in der des Geräts. Ohne die Konvertierung würde die
      // Monatsgrenze um die Zeitzonendifferenz verschoben.
      final start = DateTime(key.year, key.month, 1).toUtc();
      final end = DateTime(key.year, key.month + 1, 1).toUtc();

      // Städte-Filter (dieselbe Auswahl wie Karte/Suche/Home, siehe
      // selectedCityRegionProvider) -- venues!inner nötig, damit .eq auf
      // dem eingebetteten venues.city_id tatsächlich filtert statt nur
      // mitzuladen (PostgREST-Verhalten). city_id statt region_id: die
      // parallel gegen Produktion deployte Stadt-Erweiterung (siehe
      // 20261031000002_city_id_venues_events_sources.sql) hat city_id als
      // vollständig befüllte, kanonische Spalte etabliert (region_id blieb
      // bei einigen älteren Venues leer).
      final region = ref.watch(selectedCityRegionProvider);
      var query = Supabase.instance.client
          .from('events')
          .select(
            region == null
                ? _calendarEventColumns
                : _calendarEventColumns.replaceFirst(
                    'venues(name)',
                    'venues!inner(name)',
                  ),
          )
          .eq('status', 'scheduled')
          .gte('start_datetime', start.toIso8601String())
          .lt('start_datetime', end.toIso8601String());
      if (region != null) {
        query = query.eq('venues.city_id', region.id);
      }
      final rows = await query.order('start_datetime', ascending: true);

      final byDay = <DateTime, List<HomeEventItem>>{};
      for (final row in rows as List) {
        final map = row as Map<String, dynamic>;
        final item = HomeEventItem.fromRow(map);
        if (item.startDateTime == null) continue;
        byDay.putIfAbsent(_dayKey(item.startDateTime!), () => []).add(item);
      }
      return byDay;
    });

/// Event mit den Feldern, die ein Kalender-Eintrag braucht (Dauer, Adresse,
/// Link) statt der schlankeren [HomeEventItem] aus den Listen-Providern.
class SyncableEvent {
  const SyncableEvent({
    required this.id,
    required this.title,
    required this.start,
    this.durationMinutes,
    this.description,
    this.location,
    this.url,
  });

  final String id;
  final String title;
  final DateTime start;
  final int? durationMinutes;
  final String? description;
  final String? location;
  final String? url;

  DateTime get end => start.add(Duration(minutes: durationMinutes ?? 120));
}

/// Für den Kalender-Sync-Sheet (Apple/Google Kalender, ICS-Export): nur
/// anstehende favorisierte Events — vergangene in den Gerätekalender/eine
/// ICS zu schreiben wäre nutzlos.
final upcomingFavoriteEventsProvider =
    FutureProvider.autoDispose<List<SyncableEvent>>((ref) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return [];

      final rows = await Supabase.instance.client
          .from('favorites')
          .select(
            'events(id, title, description_de, start_datetime, duration_minutes, website_url, ticket_url, venues(name, address_street, address_zip, address_city))',
          )
          .eq('user_id', user.id);

      final now = MunichTime.now();
      final events = <SyncableEvent>[];
      for (final row in rows as List) {
        final e = row['events'] as Map<String, dynamic>?;
        if (e == null) continue;
        final start = MunichTime.tryParse(e['start_datetime'] as String?);
        if (start == null || !start.isAfter(now)) continue;

        final venue = e['venues'] as Map<String, dynamic>?;
        events.add(
          SyncableEvent(
            id: e['id'] as String,
            title: e['title'] as String? ?? '',
            start: start,
            durationMinutes: e['duration_minutes'] as int?,
            description: e['description_de'] as String?,
            location: venue == null
                ? null
                : [
                    venue['name'],
                    venue['address_street'],
                    venue['address_zip'],
                    venue['address_city'],
                  ].whereType<String>().join(', '),
            url: e['website_url'] as String? ?? e['ticket_url'] as String?,
          ),
        );
      }
      events.sort((a, b) => a.start.compareTo(b.start));
      return events;
    });

const _agendaPageSize = 200;

/// [AsyncValue]-freundliches Ergebnis für [agendaEventsProvider]: die
/// Gruppierung nach Tag plus, ob das 200er-Limit tatsächlich gegriffen hat
/// (Anzahl zurückgegebener Zeilen == Limit) — die UI zeigt in diesem Fall
/// einen Hinweis statt die Liste kommentarlos abzuschneiden.
class AgendaEvents {
  const AgendaEvents({required this.byDay, required this.truncated});

  final Map<DateTime, List<HomeEventItem>> byDay;
  final bool truncated;
}

/// Für den Agenda-Modus: chronologische Liste ab heute statt an einen
/// Kalendermonat gebunden, mit Cap statt Datumsgrenze — bei Konzerten kein
/// Bedarf für Pagination, ein Limit reicht als Schutz vor unbegrenztem Fetch.
final agendaEventsProvider = FutureProvider.autoDispose<AgendaEvents>((
  ref,
) async {
  final now = MunichTime.now();
  final region = ref.watch(selectedCityRegionProvider);
  var query = Supabase.instance.client
      .from('events')
      .select(
        region == null
            ? _calendarEventColumns
            : _calendarEventColumns.replaceFirst(
                'venues(name)',
                'venues!inner(name)',
              ),
      )
      .eq('status', 'scheduled')
      // .toUtc(): siehe Kommentar bei monthEventsProvider — derselbe Bug
      // ohne die Konvertierung.
      .gte('start_datetime', _dayKey(now).toUtc().toIso8601String());
  if (region != null) {
    query = query.eq('venues.city_id', region.id);
  }
  final rows = await query
      .order('start_datetime', ascending: true)
      .limit(_agendaPageSize);

  final byDay = <DateTime, List<HomeEventItem>>{};
  for (final row in rows as List) {
    final map = row as Map<String, dynamic>;
    final item = HomeEventItem.fromRow(map);
    if (item.startDateTime == null) continue;
    byDay.putIfAbsent(_dayKey(item.startDateTime!), () => []).add(item);
  }
  return AgendaEvents(byDay: byDay, truncated: rows.length >= _agendaPageSize);
});
