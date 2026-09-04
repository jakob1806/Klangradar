import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/events/filtered_events_providers.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/widgets/cropped_network_image.dart';
import '../../../core/widgets/event_filter_sheet.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/liquid_glass/liquid_glass.dart';
import '../../../core/constants/role_labels.dart';
import '../../../core/regions/region_providers.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/application/home_providers.dart';
import '../application/directory_providers.dart';
import '../application/natural_query_parser.dart';

final _queryProvider = StateProvider<String>((ref) => '');
final _resultTypeProvider = StateProvider.autoDispose<String>((ref) => 'all');

String _leadingUppercase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// Aus dem aktuellen Suchtext erkannte Preis-/Datumsfilter (Nutzerwunsch:
/// "Klavierkonzerte dieses Wochenende", "Mahler unter 50 Euro") — separater
/// Provider statt nur ein Feld in _searchResultsProvider, damit die UI den
/// erkannten Filter auch anzeigen kann, ohne auf den (async) Ergebnis-Future
/// zu warten.
final _parsedQueryProvider = Provider.autoDispose<ParsedSearchQuery>((ref) {
  return parseNaturalSearchQuery(ref.watch(_queryProvider));
});

final _searchResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rawQuery = ref.watch(_queryProvider).trim();
      if (rawQuery.length < 2) return [];

      final completer = Completer<void>();
      final debounce = Timer(
        const Duration(milliseconds: 350),
        completer.complete,
      );
      ref.onDispose(debounce.cancel);
      await completer.future;

      final parsed = ref.watch(_parsedQueryProvider);
      // Leerer Rest nach dem Herausfiltern von Preis-/Datumsphrasen (z.B.
      // Suchtext war nur "dieses Wochenende") — fällt auf den rohen
      // Suchtext zurück statt search_all mit einem leeren Muster
      // (matcht dann ausnahmslos alles) aufzurufen.
      final searchTerm = parsed.coreQuery.isEmpty ? rawQuery : parsed.coreQuery;

      final region = ref.watch(selectedCityRegionProvider);
      final results = await Supabase.instance.client.rpc(
        'search_all',
        // p_city_id: siehe Kommentar in map_providers.dart -- diese RPC
        // wird von der bereits live deployten city_id-basierten Version
        // bereitgestellt, nicht von einer eigenen region_id-Variante.
        params: {
          'q': searchTerm,
          'result_limit': 8,
          if (region != null) 'p_city_id': region.id,
        },
      );

      var rows = (results as List).cast<Map<String, dynamic>>();
      if (parsed.hasFilters) {
        rows = rows.where((r) {
          // Preis-/Datumsfilter gelten nur für Events — Personen/Ensembles/
          // Orte haben kein eigenes Datum/Preis, bleiben unangetastet in
          // den Ergebnissen.
          if (r['result_type'] != 'event') return true;
          if (parsed.freeOnly && r['is_free'] != true) return false;
          if (parsed.maxPrice != null) {
            final price = r['price_min'] as num?;
            final isFree = r['is_free'] == true;
            if (!isFree && (price == null || price > parsed.maxPrice!)) {
              return false;
            }
          }
          if (parsed.dateFrom != null) {
            final start = MunichTime.tryParse(r['start_datetime']);
            if (start == null ||
                start.isBefore(parsed.dateFrom!) ||
                !start.isBefore(parsed.dateTo!)) {
              return false;
            }
          }
          return true;
        }).toList();
      }

      return rows;
    });

final _searchHistoryProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final rows = await Supabase.instance.client
      .from('search_history')
      .select('query')
      .eq('user_id', user.id)
      .order('created_at', ascending: false)
      .limit(20);

  final seen = <String>{};
  for (final row in rows as List) {
    seen.add(row['query'] as String);
  }
  return seen.take(6).toList();
});

/// Läuft über eine SECURITY DEFINER-RPC statt einer View, weil
/// search_history RLS auf auth.uid() = user_id hat — eine normale Abfrage
/// würde nur die eigene Historie aggregieren, nicht die aller Nutzer.
final _trendingSearchesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final rows = await Supabase.instance.client.rpc(
    'trending_searches',
    params: {'p_result_limit': 6},
  );
  return (rows as List).map((r) => r['query'] as String).toList();
});

const _typeKeys = ['event', 'person', 'ensemble', 'venue', 'work'];

String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
  'event' => l10n.entityTypeEvents,
  'person' => l10n.entityTypePersons,
  'ensemble' => l10n.entityTypeEnsembles,
  'venue' => l10n.entityTypeVenues,
  'work' => 'Werke',
  _ => type,
};

const _typeIcon = {
  'event': Icons.event_rounded,
  'person': Icons.person_rounded,
  'ensemble': Icons.groups_rounded,
  'venue': Icons.place_rounded,
  'work': Icons.library_music_rounded,
};

const _typeRoute = {
  'event': '/event',
  'person': '/person',
  'ensemble': '/ensemble',
  'venue': '/venue',
  'work': '/work',
};

String _resultRoute(String type, Map<String, dynamic> row) {
  final identifier = type == 'work' ? row['id'] : row['slug'];
  return '${_typeRoute[type]}/$identifier';
}

/// Ausgewählter Tab im Verzeichnis-Browser ("Künstler"/"Ensembles"/"Orte"),
/// sichtbar solange kein Suchtext eingegeben ist. Nutzt dieselben
/// Typ-Schlüssel wie _typeIcon/_typeRoute ('person'/'ensemble'/'venue').
final _directoryTabProvider = StateProvider.autoDispose<String>(
  (ref) => 'person',
);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(_queryProvider.notifier).state = value;
    });
  }

  void _selectQuery(String value) {
    _debounce?.cancel();
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    ref.read(_queryProvider.notifier).state = value;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(_queryProvider);
    final resultsAsync = ref.watch(_searchResultsProvider);
    final filters = ref.watch(eventFiltersProvider);
    final resultType = ref.watch(_resultTypeProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPaddingMobile,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LiquidGlassSurface(
                    borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
                    blurSigma: AppGlassDepth.control,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _controller,
                      onChanged: _onChanged,
                      decoration: InputDecoration(
                        // isDense: sonst reserviert das InputDecorator
                        // intern mehr Höhe als der umgebende Container
                        // vorgibt (Standardverhalten für Label-Platz, auch
                        // ganz ohne labelText) — der Text stand dadurch
                        // nicht vertikal zentriert (Nutzerfeedback).
                        isDense: true,
                        border: InputBorder.none,
                        icon: Icon(
                          Icons.search_rounded,
                          color: colors.textTertiary,
                          size: 20,
                        ),
                        hintText: l10n.searchHint,
                        hintStyle: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 14,
                        ),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: colors.textTertiary,
                                  size: 18,
                                ),
                                tooltip: l10n.searchClearTooltip,
                                onPressed: () {
                                  _controller.clear();
                                  ref.read(_queryProvider.notifier).state = '';
                                },
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterButton(
                  activeCount: filters.activeCount,
                  onTap: () => showEventFilterSheet(context),
                ),
              ],
            ),
            if (!filters.isActive && query.trim().length >= 2)
              _DetectedFilterHint(
                parsed: ref.watch(_parsedQueryProvider),
                colors: colors,
              ),
            if (query.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _ResultTypeChips(
                selected: resultType,
                onSelected: (value) =>
                    ref.read(_resultTypeProvider.notifier).state = value,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Expanded(
              child: filters.isActive
                  ? ref
                        .watch(filteredEventsProvider)
                        .when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(
                            child: Text(
                              'Filter fehlgeschlagen: $e',
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                          data: (events) => _FilteredResultsList(
                            events: events,
                            colors: colors,
                          ),
                        )
                  : query.trim().length < 2
                  ? _EmptyState(colors: colors, onSelect: _selectQuery)
                  : resultsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Text(
                          'Suche fehlgeschlagen: $e',
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                      data: (results) => _ResultsList(
                        results: results,
                        colors: colors,
                        selectedType: resultType,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTypeChips extends StatelessWidget {
  const _ResultTypeChips({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const options = <(String, String)>[
      ('all', 'Alle'),
      ('person', 'Personen'),
      ('ensemble', 'Ensembles'),
      ('venue', 'Venues'),
      ('event', 'Veranstaltungen'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return ChoiceChip(
            label: Text(option.$2),
            selected: selected == option.$1,
            onSelected: (_) => onSelected(option.$1),
          );
        },
      ),
    );
  }
}

/// Zeigt, welche Preis-/Datumsfilter aus dem Freitext erkannt wurden
/// (Nutzerwunsch: "Klavierkonzerte dieses Wochenende", "Mahler unter 50
/// Euro") — reine Transparenz, kein eigenes UI zum Ändern (dafür gibt es
/// bereits den Filter-Button/EventFilterSheet).
class _DetectedFilterHint extends StatelessWidget {
  const _DetectedFilterHint({required this.parsed, required this.colors});

  final ParsedSearchQuery parsed;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    if (!parsed.hasFilters) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;

    final labels = [
      if (parsed.freeOnly) l10n.searchFilterFree,
      if (parsed.maxPrice != null)
        l10n.searchFilterUpTo(parsed.maxPrice!.toStringAsFixed(0)),
      if (parsed.dateFrom != null)
        '${parsed.dateFrom!.day}.${parsed.dateFrom!.month}.–${parsed.dateTo!.subtract(const Duration(days: 1)).day}.${parsed.dateTo!.subtract(const Duration(days: 1)).month}.',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 14,
            color: colors.accentPrimary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.searchDetectedFilters(labels.join(' · ')),
              style: TextStyle(color: colors.accentPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final active = activeCount > 0;
    return Semantics(
      button: true,
      label: active
          ? l10n.searchFilterLabelActive(activeCount)
          : l10n.searchFilterLabel,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.accentPrimary : colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: active ? colors.accentPrimary : colors.separator,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.tune_rounded,
                color: active ? Colors.white : colors.textSecondary,
                size: 20,
              ),
              if (active)
                Positioned(
                  right: -6,
                  top: -6,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accentSecondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$activeCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilteredResultsList extends StatelessWidget {
  const _FilteredResultsList({required this.events, required this.colors});

  final List<HomeEventItem> events;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.searchNoFilterResults,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => Divider(color: colors.separator, height: 1),
      itemBuilder: (context, i) {
        final e = events[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(
            width: 48,
            height: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: e.imageUrl == null
                  ? GenreArtwork(genre: e.genre)
                  : CachedNetworkImage(
                      imageUrl: e.imageUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          GenreArtwork(genre: e.genre),
                      errorWidget: (context, url, error) =>
                          GenreArtwork(genre: e.genre),
                    ),
            ),
          ),
          title: Text(
            e.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          subtitle: Text(
            e.venueAndTime,
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
          ),
          onTap: () => context.push('/event/${e.slug}'),
        );
      },
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.colors, required this.onSelect});
  final AppColorsExtension colors;
  final ValueChanged<String> onSelect;

  // Fallback, solange trending_searches() mangels echter Nutzung noch
  // nichts liefert — sobald genug Suchvolumen da ist, gewinnt das Echte.
  static const _fallbackSuggestions = [
    'Bach',
    'Kirchenmusik',
    'Herkulessaal',
    'Kostenlos',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final historyAsync = ref.watch(_searchHistoryProvider);
    final trending =
        ref.watch(_trendingSearchesProvider).valueOrNull ?? const [];
    final suggestions = trending.isEmpty ? _fallbackSuggestions : trending;
    final directoryTab = ref.watch(_directoryTabProvider);

    return ListView(
      children: [
        historyAsync.maybeWhen(
          data: (history) => history.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.searchHistoryTitle,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(letterSpacing: 1),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final q in history)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.history_rounded,
                            color: colors.textTertiary,
                            size: 20,
                          ),
                          title: Text(
                            q,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textPrimary,
                            ),
                          ),
                          onTap: () => onSelect(q),
                        ),
                    ],
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        Text(
          l10n.searchTrendingTitle,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(letterSpacing: 1),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions
              .map(
                (c) => ActionChip(label: Text(c), onPressed: () => onSelect(c)),
              )
              .toList(),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Lass dich inspirieren',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _InspirationGrid(colors: colors, onSelect: onSelect),
        const SizedBox(height: AppSpacing.xl),
        Text(
          l10n.searchBrowseTitle,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(letterSpacing: 1),
        ),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'person', label: Text(l10n.entityTypeArtists)),
            ButtonSegment(
              value: 'ensemble',
              label: Text(l10n.entityTypeEnsembles),
            ),
            ButtonSegment(value: 'venue', label: Text(l10n.entityTypeVenues)),
          ],
          selected: {directoryTab},
          onSelectionChanged: (selection) =>
              ref.read(_directoryTabProvider.notifier).state = selection.first,
        ),
        const SizedBox(height: AppSpacing.sm),
        _DirectoryEntries(type: directoryTab, colors: colors),
      ],
    );
  }
}

class _InspirationGrid extends StatelessWidget {
  const _InspirationGrid({required this.colors, required this.onSelect});

  final AppColorsExtension colors;
  final ValueChanged<String> onSelect;

  static const _items = <(String, IconData, Color)>[
    ('Oper & Musiktheater', Icons.theater_comedy_rounded, Color(0xFF7950C7)),
    ('Freier Eintritt', Icons.confirmation_number_rounded, Color(0xFF168B82)),
    ('Kammermusik', Icons.music_note_rounded, Color(0xFF3F51A6)),
    ('Große Symphonik', Icons.groups_rounded, Color(0xFF286DA8)),
    ('Chor & Vokalmusik', Icons.record_voice_over_rounded, Color(0xFFC44370)),
    ('Neue Musik', Icons.graphic_eq_rounded, Color(0xFFD46632)),
    ('Orgel', Icons.piano_rounded, Color(0xFF277C75)),
    ('Lied & Gesang', Icons.mic_rounded, Color(0xFF7350A9)),
    ('Klavier', Icons.piano_rounded, Color(0xFF356BA8)),
    ('Alte Musik', Icons.history_edu_rounded, Color(0xFFA85C32)),
    ('Ballett & Tanz', Icons.auto_awesome_rounded, Color(0xFF8A4DA1)),
    ('Familienkonzerte', Icons.family_restroom_rounded, Color(0xFF32877D)),
    ('Barock', Icons.music_note_rounded, Color(0xFFB8672D)),
    ('Romantik', Icons.favorite_rounded, Color(0xFFB64268)),
    ('Open Air', Icons.wb_sunny_rounded, Color(0xFF248C83)),
    ('Premieren', Icons.star_rounded, Color(0xFFB64578)),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _items.map((item) {
            return SizedBox(
              width: width,
              height: 104,
              child: Material(
                color: item.$3,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(item.$1),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Icon(item.$2, size: 44, color: Colors.white24),
                        ),
                        Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            item.$1,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _DirectoryEntries extends ConsumerWidget {
  const _DirectoryEntries({required this.type, required this.colors});

  final String type;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Map<String, dynamic>>> async = switch (type) {
      'ensemble' => ref.watch(allEnsemblesProvider),
      'venue' => ref.watch(allVenuesProvider),
      _ => ref.watch(allPersonsProvider),
    };

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          AppLocalizations.of(context)!.loadingFailed(e.toString()),
          style: TextStyle(color: colors.error),
        ),
      ),
      data: (rows) => _DirectoryList(type: type, rows: rows, colors: colors),
    );
  }
}

/// Miniaturbild statt generischem Typ-Icon, sobald ein `photo_url`
/// vorhanden ist (bisher zeigte jede Zeile in Verzeichnis- wie
/// Suchergebnisliste nur ein Icon — Nutzerfeedback: Künstler-Miniaturbilder
/// fehlten komplett). Fällt bei fehlendem/kaputtem Bild auf das bisherige
/// Icon zurück, ändert also für Typen ohne photo_url (aktuell event/
/// ensemble/venue in der Ergebnisliste) nichts.
///
/// [crop] ist der im Admin redaktionell festgelegte runde Avatar-Ausschnitt
/// (persons/ensembles.avatar_crop_x/y/width/height) — `null` bedeutet kein
/// Ausschnitt gewählt, dann bleibt es beim bisherigen zentrierten
/// BoxFit.cover (siehe CroppedNetworkImage-Fallback).
class _EntryLeading extends StatelessWidget {
  const _EntryLeading({
    required this.type,
    required this.photoUrl,
    required this.colors,
    this.crop,
  });

  final String type;
  final String? photoUrl;
  final AppColorsExtension colors;
  final Rect? crop;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(_typeIcon[type], color: colors.accentPrimary, size: 22);
    // Feste SizedBox um Icon UND Bild — sonst reserviert ListTile je nach
    // intrinsischer Breite des leading-Widgets unterschiedlich viel Platz
    // (22px-Icon vs. 36px-Bild), wodurch der Titeltext zeilenweise an
    // unterschiedlichen x-Positionen begann (Nutzerfeedback: "nicht alle
    // sind auf einer x Ebene").
    if (photoUrl == null || photoUrl!.isEmpty) {
      return SizedBox(
        width: _size,
        height: _size,
        child: Center(child: icon),
      );
    }

    return SizedBox(
      width: _size,
      height: _size,
      child: ClipOval(
        child: CroppedNetworkImage(
          imageUrl: photoUrl!,
          crop: crop,
          placeholder: (context) => icon,
          errorWidget: (context) => icon,
        ),
      ),
    );
  }
}

/// Liest einen [Rect]-Ausschnitt aus den `avatar_crop_x/y/width/height`-
/// Spalten einer Verzeichniszeile — analog zu `GalleryImage.fromRow`
/// (entity_gallery_providers.dart) für die 16:9-Galerie-Crops.
Rect? _avatarCropFromRow(Map<String, dynamic> r) {
  final x = (r['avatar_crop_x'] as num?)?.toDouble();
  final y = (r['avatar_crop_y'] as num?)?.toDouble();
  final width = (r['avatar_crop_width'] as num?)?.toDouble();
  final height = (r['avatar_crop_height'] as num?)?.toDouble();
  if (x == null || y == null || width == null || height == null) return null;
  return Rect.fromLTWH(x, y, width, height);
}

class _DirectoryList extends StatelessWidget {
  const _DirectoryList({
    required this.type,
    required this.rows,
    required this.colors,
  });

  final String type;
  final List<Map<String, dynamic>> rows;
  final AppColorsExtension colors;

  String _title(Map<String, dynamic> r) => switch (type) {
    'ensemble' || 'venue' => r['name'] as String? ?? '',
    _ => r['full_name'] as String? ?? '',
  };

  String? _subtitle(AppLocalizations l10n, Map<String, dynamic> r) {
    switch (type) {
      case 'ensemble':
        final t = r['type'] as String?;
        return t == null ? null : (ensembleTypeLabels(l10n)[t] ?? t);
      case 'venue':
        return r['address_city'] as String?;
      default:
        final roles = (r['roles'] as List?)?.cast<String>() ?? [];
        if (roles.isEmpty) return null;
        final labels = personRoleLabels(l10n);
        return roles.map((role) => labels[role] ?? role).join(' · ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          l10n.searchDirectoryEmpty,
          style: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      );
    }

    return Column(
      children: [
        for (final r in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _EntryLeading(
              type: type,
              photoUrl: r['photo_url'] as String?,
              colors: colors,
              crop: _avatarCropFromRow(r),
            ),
            title: Text(
              _title(r),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            subtitle: _subtitle(l10n, r) != null
                ? Text(
                    _leadingUppercase(_subtitle(l10n, r)!),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                    ),
                  )
                : null,
            onTap: () {
              Haptics.light();
              context.push(_resultRoute(type, r));
            },
          ),
      ],
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.results,
    required this.colors,
    required this.selectedType,
  });
  final List<Map<String, dynamic>> results;
  final AppColorsExtension colors;
  final String selectedType;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (results.isEmpty) {
      return Center(
        child: Text(
          l10n.searchNoResults,
          style: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      );
    }

    final visibleResults = selectedType == 'all'
        ? results
        : results.where((row) => row['result_type'] == selectedType).toList();
    if (visibleResults.isEmpty) {
      return Center(
        child: Text(
          l10n.searchNoResults,
          style: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      );
    }
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in visibleResults) {
      grouped.putIfAbsent(r['result_type'] as String, () => []).add(r);
    }

    return ListView(
      children: [
        for (final type in _typeKeys)
          if (grouped[type] != null) ...[
            Text(
              _typeLabel(l10n, type),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            for (final r in grouped[type]!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _EntryLeading(
                  type: type,
                  photoUrl: r['photo_url'] as String?,
                  colors: colors,
                ),
                title: Text(
                  r['title'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: r['subtitle'] != null
                    ? Text(
                        _leadingUppercase(r['subtitle'] as String),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      )
                    : null,
                onTap: () {
                  Haptics.light();
                  context.push(_resultRoute(type, r));
                },
              ),
            const SizedBox(height: AppSpacing.lg),
          ],
      ],
    );
  }
}
