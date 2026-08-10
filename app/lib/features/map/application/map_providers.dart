import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/time/munich_time.dart';

class MapVenue {
  const MapVenue({
    required this.id,
    required this.slug,
    required this.name,
    required this.addressCity,
    required this.lat,
    required this.lng,
    required this.upcomingEventCount,
  });

  final String id;
  final String slug;
  final String name;
  final String? addressCity;
  final double lat;
  final double lng;
  final int upcomingEventCount;

  factory MapVenue.fromRow(Map<String, dynamic> row) {
    return MapVenue(
      id: row['id'] as String,
      slug: row['slug'] as String,
      name: row['name'] as String? ?? '',
      addressCity: row['address_city'] as String?,
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lng'] as num).toDouble(),
      upcomingEventCount: (row['upcoming_event_count'] as num?)?.toInt() ?? 0,
    );
  }
}

final mapVenuesProvider = FutureProvider.autoDispose<List<MapVenue>>((
  ref,
) async {
  final rows = await Supabase.instance.client.rpc('venues_with_latlng');
  return (rows as List)
      .map((r) => MapVenue.fromRow(r as Map<String, dynamic>))
      .toList();
});

/// Kompaktes Event für die Vorschau-Liste im Karten-Bottom-Sheet
/// (_VenuePreviewSheet) — bewusst schlanker als HomeEventItem, weil dort
/// nur Titel + Datum/Uhrzeit angezeigt werden, kein Venue-/Genre-Join nötig.
class VenueUpcomingEvent {
  const VenueUpcomingEvent({
    required this.id,
    required this.slug,
    required this.title,
    required this.startDateTime,
    this.imageUrl,
  });

  final String id;
  final String slug;
  final String title;
  final DateTime? startDateTime;
  final String? imageUrl;

  factory VenueUpcomingEvent.fromRow(Map<String, dynamic> row) {
    final imageUrls = row['image_urls'] as List?;
    return VenueUpcomingEvent(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String? ?? '',
      startDateTime: MunichTime.tryParse(row['start_datetime'] as String?),
      imageUrl: (imageUrls != null && imageUrls.isNotEmpty)
          ? imageUrls.first as String?
          : null,
    );
  }
}

/// Liefert bis zu 5 kommende, veröffentlichte Veranstaltungen einer Venue
/// für die Vorschau-Liste im Karten-Bottom-Sheet. Spiegelt bewusst die
/// Query-Form von venue_detail_screen.dart (dort clientseitig gefiltert),
/// filtert hier aber serverseitig auf status=scheduled und
/// start_datetime >= jetzt, damit die Liste kurz bleibt.
final venueUpcomingEventsProvider = FutureProvider.autoDispose
    .family<List<VenueUpcomingEvent>, String>((ref, venueId) async {
      final rows = await Supabase.instance.client
          .from('events')
          .select('id, slug, title, start_datetime, image_urls')
          .eq('venue_id', venueId)
          .eq('status', 'scheduled')
          .gte('start_datetime', DateTime.now().toIso8601String())
          .order('start_datetime', ascending: true)
          .limit(5);
      return (rows as List)
          .map((r) => VenueUpcomingEvent.fromRow(r as Map<String, dynamic>))
          .toList();
    });
