import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/events/filtered_events_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/event_filter_sheet.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../home/application/home_providers.dart';
import '../application/directory_providers.dart';

final _queryProvider = StateProvider<String>((ref) => '');

final _searchResultsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final query = ref.watch(_queryProvider).trim();
      if (query.length < 2) return [];

      final results = await Supabase.instance.client.rpc(
        'search_all',
        params: {'q': query, 'result_limit': 8},
      );

      final user = ref.read(currentUserProvider);
      if (user != null) {
        unawaited(
          Supabase.instance.client.from('search_history').insert({
            'user_id': user.id,
            'query': query,
          }),
        );
      }

      return (results as List).cast<Map<String, dynamic>>();
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

const _typeLabel = {
  'event': 'Veranstaltungen',
  'person': 'Personen',
  'ensemble': 'Ensembles',
  'venue': 'Orte',
};

const _typeIcon = {
  'event': Icons.event_rounded,
  'person': Icons.person_rounded,
  'ensemble': Icons.groups_rounded,
  'venue': Icons.place_rounded,
};

const _typeRoute = {
  'event': '/event',
  'person': '/person',
  'ensemble': '/ensemble',
  'venue': '/venue',
};

const _ensembleTypeLabel = {
  'chor': 'Chor',
  'orchester': 'Orchester',
  'kammerensemble': 'Kammerensemble',
  'big_band': 'Big Band',
  'sonstiges': 'Ensemble',
};

const _personRoleLabel = {
  'komponist': 'Komponist:in',
  'dirigent': 'Dirigent:in',
  'solist': 'Solist:in',
  'chorleiter': 'Chorleiter:in',
  'moderator': 'Moderator:in',
};

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
    final query = ref.watch(_queryProvider);
    final resultsAsync = ref.watch(_searchResultsProvider);
    final filters = ref.watch(eventFiltersProvider);

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
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      border: Border.all(color: colors.separator),
                    ),
                    child: TextField(
                      controller: _controller,
                      onChanged: _onChanged,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        icon: Icon(
                          Icons.search_rounded,
                          color: colors.textTertiary,
                          size: 20,
                        ),
                        hintText: 'Werk, Komponist, Ensemble, Ort …',
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
                                tooltip: 'Suche löschen',
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
                      data: (results) =>
                          _ResultsList(results: results, colors: colors),
                    ),
            ),
          ],
        ),
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
    final active = activeCount > 0;
    return Semantics(
      button: true,
      label: active ? 'Filter, $activeCount aktiv' : 'Filter',
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
          'Keine Veranstaltungen für diese Filter.',
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
              child: GenreArtwork(genre: e.genre),
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
                        'Suchverlauf',
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
          'Beliebte Suchen',
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
          'Durchstöbern',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(letterSpacing: 1),
        ),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'person', label: Text('Künstler')),
            ButtonSegment(value: 'ensemble', label: Text('Ensembles')),
            ButtonSegment(value: 'venue', label: Text('Orte')),
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
          'Laden fehlgeschlagen: $e',
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
class _EntryLeading extends StatelessWidget {
  const _EntryLeading({
    required this.type,
    required this.photoUrl,
    required this.colors,
  });

  final String type;
  final String? photoUrl;
  final AppColorsExtension colors;

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
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          placeholder: (context, url) => icon,
          errorWidget: (context, url, error) => icon,
        ),
      ),
    );
  }
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

  String? _subtitle(Map<String, dynamic> r) {
    switch (type) {
      case 'ensemble':
        final t = r['type'] as String?;
        return t == null ? null : (_ensembleTypeLabel[t] ?? t);
      case 'venue':
        return r['address_city'] as String?;
      default:
        final roles = (r['roles'] as List?)?.cast<String>() ?? [];
        if (roles.isEmpty) return null;
        return roles.map((role) => _personRoleLabel[role] ?? role).join(' · ');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'Keine Einträge.',
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
            ),
            title: Text(
              _title(r),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            subtitle: _subtitle(r) != null
                ? Text(
                    _subtitle(r)!,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                    ),
                  )
                : null,
            onTap: () => context.push('${_typeRoute[type]}/${r['slug']}'),
          ),
      ],
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, required this.colors});
  final List<Map<String, dynamic>> results;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'Keine Treffer.',
          style: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      );
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in results) {
      grouped.putIfAbsent(r['result_type'] as String, () => []).add(r);
    }

    return ListView(
      children: [
        for (final type in _typeLabel.keys)
          if (grouped[type] != null) ...[
            Text(
              '${_typeLabel[type]}',
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
                        r['subtitle'],
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      )
                    : null,
                onTap: () => context.push('${_typeRoute[type]}/${r['slug']}'),
              ),
            const SizedBox(height: AppSpacing.lg),
          ],
      ],
    );
  }
}
