import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/events/event_filters.dart';
import '../../../core/events/filtered_events_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/external_maps.dart';
import '../../../core/widgets/event_filter_sheet.dart';
import '../application/map_providers.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  static const _muenchenCenter = LatLng(48.1351, 11.5820);
  static const _muenchenZoom = 12.5;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final venuesAsync = ref.watch(mapVenuesProvider);
    final filters = ref.watch(eventFiltersProvider);
    final allVenues = venuesAsync.valueOrNull ?? const <MapVenue>[];

    final filteredEventsAsync = filters.isActive
        ? ref.watch(filteredEventsProvider)
        : null;
    final matchingVenueIds = filteredEventsAsync?.valueOrNull
        ?.map((e) => e.venueId)
        .whereType<String>()
        .toSet();
    final venues = matchingVenueIds == null
        ? allVenues
        : allVenues.where((v) => matchingVenueIds.contains(v.id)).toList();
    final venueById = {for (final v in venues) v.id: v};

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: MapScreen._muenchenCenter,
            initialZoom: MapScreen._muenchenZoom,
            minZoom: 10,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'de.klassikmuenchen.klassik_muenchen',
            ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 60,
                size: const Size(36, 36),
                markers: [
                  for (final venue in venues)
                    Marker(
                      key: ValueKey<String>(venue.id),
                      point: LatLng(venue.lat, venue.lng),
                      width: 34,
                      height: 34,
                      alignment: Alignment.topCenter,
                      child: _VenuePin(color: colors.accentPrimary),
                    ),
                ],
                builder: (context, markers) => _ClusterBubble(
                  count: markers.length,
                  color: colors.accentPrimary,
                ),
                onMarkerTap: (marker) {
                  final key = marker.key;
                  if (key is! ValueKey<String>) return;
                  final venue = venueById[key.value];
                  if (venue != null) _showVenueSheet(context, venue);
                },
              ),
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  '© OpenStreetMap-Mitwirkende',
                  onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (venuesAsync.isLoading && !venuesAsync.hasValue)
          const Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(child: CircularProgressIndicator()),
          ),
        Positioned(
          top: AppSpacing.md,
          left: AppSpacing.screenPaddingMobile,
          right: AppSpacing.screenPaddingMobile,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FilterBar(filters: filters),
                if (venuesAsync.hasError) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ErrorBanner(message: '${venuesAsync.error}'),
                ],
                if (filteredEventsAsync?.hasError ?? false) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ErrorBanner(message: '${filteredEventsAsync!.error}'),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          right: AppSpacing.screenPaddingMobile,
          bottom: AppSpacing.lg,
          child: SafeArea(
            top: false,
            child: _RecenterButton(
              color: colors.backgroundElevated,
              iconColor: colors.textPrimary,
              onTap: () => _mapController.move(
                MapScreen._muenchenCenter,
                MapScreen._muenchenZoom,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showVenueSheet(BuildContext context, MapVenue venue) {
    showModalBottomSheet(
      context: context,
      // isScrollControlled + die SingleChildScrollView in
      // _VenuePreviewSheet: ohne beides überschreitet der Inhalt (Name,
      // Adresse, bis zu 5 Eventzeilen, Buttons) auf kleineren Geräten die
      // Standardhöhe eines nicht scrollbaren Bottom-Sheets und überläuft
      // (live beobachtet: "BOTTOM OVERFLOWED BY 119 PIXELS" bei Venues mit
      // mehreren kommenden Veranstaltungen).
      isScrollControlled: true,
      builder: (_) => _VenuePreviewSheet(venue: venue),
    );
  }
}

class _VenuePin extends StatelessWidget {
  const _VenuePin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}

class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// "FilterBar (oben, horizontal scrollbar Chips)" laut
/// docs/05-navigation-structure.md. Öffnet dieselbe FilterSheet wie die
/// Suche (geteilter eventFiltersProvider) statt einer Karte-eigenen
/// Filter-Implementierung; Barrierefrei/Open Air zusätzlich als
/// Direkt-Umschalter, weil das die zwei häufigsten Einzelfilter beim
/// spontanen Kartenblättern sein dürften.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters});

  final EventFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _BarChip(
            label: filters.activeCount > 0
                ? 'Filter (${filters.activeCount})'
                : 'Filter',
            icon: Icons.tune_rounded,
            active: filters.activeCount > 0,
            onTap: () => showEventFilterSheet(context),
          ),
          const SizedBox(width: 8),
          _BarChip(
            label: 'Barrierefrei',
            active: filters.accessibleOnly,
            onTap: () =>
                ref.read(eventFiltersProvider.notifier).state = EventFilters(
                  dateRange: filters.dateRange,
                  genreIds: filters.genreIds,
                  maxPrice: filters.maxPrice,
                  accessibleOnly: !filters.accessibleOnly,
                  openAirOnly: filters.openAirOnly,
                  maxDistanceKm: filters.maxDistanceKm,
                ),
          ),
          const SizedBox(width: 8),
          _BarChip(
            label: 'Open Air',
            active: filters.openAirOnly,
            onTap: () =>
                ref.read(eventFiltersProvider.notifier).state = EventFilters(
                  dateRange: filters.dateRange,
                  genreIds: filters.genreIds,
                  maxPrice: filters.maxPrice,
                  accessibleOnly: filters.accessibleOnly,
                  openAirOnly: !filters.openAirOnly,
                  maxDistanceKm: filters.maxDistanceKm,
                ),
          ),
          if (filters.isActive) ...[
            const SizedBox(width: 8),
            _BarChip(
              label: 'Zurücksetzen',
              icon: Icons.close_rounded,
              active: false,
              onTap: () => ref.read(eventFiltersProvider.notifier).state =
                  EventFilters.empty,
            ),
          ],
        ],
      ),
    );
  }
}

class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: active ? colors.accentPrimary : colors.backgroundElevated,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          // vertical war 9 (~33px Gesamthöhe) — unter der 44px-Mindest-
          // Tap-Fläche, siehe Barrierefreiheits-Audit.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: active ? Colors.white : colors.textSecondary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Setzt die Karte zurück auf München-Zentrum/Standardzoom (Nutzerwunsch:
/// "einen Button in der Karte, der die Map wieder neu ausrichtet") —
/// relevant, sobald man sich beim Erkunden weit weg gezoomt/gescrollt hat.
class _RecenterButton extends StatelessWidget {
  const _RecenterButton({
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.my_location_rounded, size: 22, color: iconColor),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      color: colors.backgroundElevated,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          'Karte konnte nicht geladen werden: $message',
          style: TextStyle(color: colors.error, fontSize: 12.5),
        ),
      ),
    );
  }
}

class _VenuePreviewSheet extends ConsumerWidget {
  const _VenuePreviewSheet({required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final eventsAsync = ref.watch(venueUpcomingEventsProvider(venue.id));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPaddingMobile,
            AppSpacing.lg,
            AppSpacing.screenPaddingMobile,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(venue.name, style: Theme.of(context).textTheme.titleLarge),
              if (venue.addressCity != null) ...[
                const SizedBox(height: 4),
                Text(
                  venue.addressCity!,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                venue.upcomingEventCount > 0
                    ? '${venue.upcomingEventCount} kommende Veranstaltung${venue.upcomingEventCount == 1 ? '' : 'en'}'
                    : 'Keine kommenden Veranstaltungen',
                style: TextStyle(color: colors.textTertiary, fontSize: 13),
              ),
              if (venue.upcomingEventCount > 0)
                eventsAsync.when(
                  data: (events) => events.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            children: [
                              for (final event in events)
                                _VenueSheetEventRow(
                                  event: event,
                                  colors: colors,
                                ),
                            ],
                          ),
                        ),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openExternalMaps(
                        lat: venue.lat,
                        lng: venue.lng,
                        name: venue.name,
                      ),
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Route'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/venue/${venue.slug}');
                      },
                      child: const Text('Details ansehen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kompakte Zeile für eine kommende Veranstaltung im Karten-Bottom-Sheet.
/// Schließt das Sheet vor der Navigation, analog zum "Details ansehen"-
/// Button oben und zu _VenueEventRow in venue_detail_screen.dart.
class _VenueSheetEventRow extends StatelessWidget {
  const _VenueSheetEventRow({required this.event, required this.colors});

  final VenueUpcomingEvent event;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final start = event.startDateTime;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
          color: colors.textPrimary,
        ),
      ),
      subtitle: start != null
          ? Text(
              _formatSheetDateTime(start),
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: colors.textTertiary,
      ),
      onTap: () {
        Navigator.of(context).pop();
        context.push('/event/${event.slug}');
      },
    );
  }
}

String _formatSheetDateTime(DateTime d) {
  final date = '${d.day}.${d.month}.${d.year}';
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}
