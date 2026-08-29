import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/events/event_filters.dart';
import '../../../core/events/filtered_events_providers.dart';
import '../../../core/interests/interests_providers.dart';
import '../../../core/regions/region_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/external_maps.dart';
import '../../../core/widgets/event_filter_sheet.dart';
import '../../../l10n/generated/app_localizations.dart';
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
  LatLng? _userLocation;

  /// Verhindert, dass die Karte den Nutzer nach einem manuellen Pan/Zoom
  /// wieder zurückzentriert — nur der ERSTE erfolgreiche Fix (Standort oder
  /// geladene Venues) darf die initiale Münchner Kamera ersetzen. Ohne das
  /// wären Venues in anderen Städten (Berlin/Hamburg/Frankfurt/Wien, siehe
  /// Stadt-Erweiterung) unsichtbar, bis man manuell dorthin scrollt/zoomt.
  bool _autoFitDone = false;

  @override
  void initState() {
    super.initState();
    _loadUserLocation();
  }

  void _autoFitToVenuesIfNeeded(List<MapVenue> venues) {
    if (_autoFitDone || _userLocation != null || venues.isEmpty) return;
    _autoFitDone = true;
    if (venues.length == 1) {
      _mapController.move(
        LatLng(venues.first.lat, venues.first.lng),
        MapScreen._muenchenZoom,
      );
      return;
    }
    final bounds = LatLngBounds.fromPoints([
      for (final v in venues) LatLng(v.lat, v.lng),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
      );
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Fragt die Standortberechtigung an und holt einmalig die aktuelle
  /// Position — Nutzeranfrage: "die App muss noch auf den Standort
  /// zugreifen, damit man auf der Karte sieht, wo man ist". Bewusst ein
  /// einzelner getCurrentPosition()-Aufruf statt eines Live-Streams: die
  /// Karte muss nur zeigen, wo man ungefähr ist, kein Turn-by-Turn-Tracking,
  /// das würde nur unnötig Akku kosten. Scheitert leise (keine
  /// Fehlermeldung) bei fehlender Berechtigung/deaktivierten
  /// Standortdiensten — der blaue Punkt fehlt dann einfach, die Karte
  /// bleibt trotzdem voll nutzbar.
  Future<void> _loadUserLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });
      if (!_autoFitDone) {
        _autoFitDone = true;
        _mapController.move(_userLocation!, MapScreen._muenchenZoom);
      }
    } catch (_) {
      // Standort ist eine Zusatzfunktion, kein Blocker für die Karte —
      // jeder Fehler (Timeout, Plattform-Ausnahme, ...) bleibt lautlos.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    // Ein Städtewechsel muss die Kamera neu auf die dann geladenen Venues
    // ausrichten dürfen -- sonst bliebe sie auf der vorherigen Stadt stehen.
    ref.listen(selectedCityRegionProvider, (previous, next) {
      if (previous?.id != next?.id) {
        setState(() => _autoFitDone = false);
      }
    });
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

    _autoFitToVenuesIfNeeded(allVenues);

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
            if (_userLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userLocation!,
                    width: 22,
                    height: 22,
                    child: const _UserLocationDot(),
                  ),
                ],
              ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  l10n.mapAttribution,
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
              // Zentriert auf den Nutzerstandort, sonst auf alle aktuell
              // geladenen (ggf. stadtgefilterten) Venues -- nicht mehr fix
              // auf München, das wäre bei einer anderen ausgewählten Stadt
              // (oder für Nutzer:innen außerhalb Münchens) irreführend.
              onTap: () {
                if (_userLocation != null) {
                  _mapController.move(_userLocation!, MapScreen._muenchenZoom);
                } else if (allVenues.isNotEmpty) {
                  _autoFitDone = false;
                  _autoFitToVenuesIfNeeded(allVenues);
                } else {
                  _mapController.move(
                    MapScreen._muenchenCenter,
                    MapScreen._muenchenZoom,
                  );
                }
              },
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

/// Blauer "Wo bin ich"-Punkt im gängigen Kartenapp-Stil (weißer Ring, blauer
/// Kern) — bewusst optisch klar von den roten Veranstaltungsort-Pins
/// unterschieden.
class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2E7BE0),
          shape: BoxShape.circle,
        ),
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
/// Filter-Implementierung. Nutzeranfrage: "die zwei vorschläge
/// 'barrierefrei' und 'openair' sollen von dort entfernt werden. neben dem
/// button 'filter' soll (leicht rot eingefärbt) immer nur die kategorien
/// stehen, die ausgewählt wurden. wenn man die ausgewählten kategorien
/// anklickt, sollen sie wieder entwählt werden." — die Direkt-Umschalter
/// sind komplett weg, stattdessen zeigt die Leiste die aktuell gewählten
/// Genres als eigene Chips, die per Tap wieder entfernt werden.
void _showCityPicker(
  BuildContext context,
  WidgetRef ref,
  List<CityRegion> cities,
  CityRegion? selected,
) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioGroup<String?>(
            groupValue: selected?.id,
            onChanged: (value) {
              CityRegion? next;
              for (final city in cities) {
                if (city.id == value) {
                  next = city;
                  break;
                }
              }
              ref.read(selectedCityRegionProvider.notifier).state = next;
              Navigator.of(sheetContext).pop();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RadioListTile<String?>(
                  title: Text('Alle Städte'),
                  value: null,
                ),
                for (final city in cities)
                  RadioListTile<String?>(
                    title: Text(city.name),
                    value: city.id,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters});

  final EventFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final genres = ref.watch(genreOptionsProvider).valueOrNull ?? const [];
    final genreLabels = {for (final g in genres) g.id: g.label};
    final cities = ref.watch(activeCityRegionsProvider).valueOrNull ?? const [];
    final selectedCity = ref.watch(selectedCityRegionProvider);

    void removeGenre(String genreId) {
      ref.read(eventFiltersProvider.notifier).state = EventFilters(
        dateRange: filters.dateRange,
        genreIds: filters.genreIds.where((id) => id != genreId).toSet(),
        maxPrice: filters.maxPrice,
        accessibleOnly: filters.accessibleOnly,
        openAirOnly: filters.openAirOnly,
        maxDistanceKm: filters.maxDistanceKm,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Nur relevant, seit es mehr als eine aktive Stadt gibt (Berlin/
          // Hamburg/Frankfurt/Wien neben München) -- vorher wäre ein
          // Städte-Chip mit genau einer Option sinnlos gewesen.
          if (cities.length > 1) ...[
            _BarChip(
              label: selectedCity?.name ?? 'Alle Städte',
              icon: Icons.location_city_rounded,
              active: selectedCity != null,
              onTap: () => _showCityPicker(context, ref, cities, selectedCity),
            ),
            const SizedBox(width: 8),
          ],
          _BarChip(
            label: filters.activeCount > 0
                ? l10n.mapFilterLabelCount(filters.activeCount)
                : l10n.mapFilterLabel,
            icon: Icons.tune_rounded,
            active: filters.activeCount > 0,
            onTap: () => showEventFilterSheet(context),
          ),
          for (final genreId in filters.genreIds) ...[
            const SizedBox(width: 8),
            _SelectedGenreChip(
              label: genreLabels[genreId] ?? genreId,
              onTap: () => removeGenre(genreId),
            ),
          ],
          if (filters.isActive) ...[
            const SizedBox(width: 8),
            _BarChip(
              label: l10n.mapFilterReset,
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

/// Chip für ein aktuell ausgewähltes Genre — leicht rot eingefärbt, wandert
/// bei Tap wieder aus dem Filter raus (siehe _FilterBar.removeGenre).
class _SelectedGenreChip extends StatelessWidget {
  const _SelectedGenreChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const chipColor = Color(0xFFFCE4E4);
    const textColor = Color(0xFFB3261E);
    return Material(
      color: chipColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.close_rounded, size: 14, color: textColor),
            ],
          ),
        ),
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
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.mapRecenter,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ExcludeSemantics(
              child: Icon(
                Icons.my_location_rounded,
                size: 22,
                color: iconColor,
              ),
            ),
          ),
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
          AppLocalizations.of(context)!.mapLoadError(message),
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
    final l10n = AppLocalizations.of(context)!;
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
                    ? l10n.mapVenueUpcomingCount(venue.upcomingEventCount)
                    : l10n.mapVenueNoUpcoming,
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
                      label: Text(l10n.venueRoute),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/venue/${venue.slug}');
                      },
                      child: Text(l10n.mapViewDetails),
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
