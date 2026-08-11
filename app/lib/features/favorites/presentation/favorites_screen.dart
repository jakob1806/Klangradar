import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/favorites/favorites_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/application/home_providers.dart';

typedef _FavoriteRow = ({
  HomeEventItem event,
  FavoriteStatus status,
  // Für die Suche über "Datum, Künstler, Werk oder Veranstaltungsort"
  // (Nutzerwunsch Punkt 1) — ein einziger vorab zusammengesetzter,
  // kleingeschriebener Text statt eines strukturierten Modells: die Suche
  // hier ist bewusst ein einfacher Volltext-Filter, kein separates
  // Facetten-UI je Feld.
  String searchText,
});

/// Sortiert nach Konzertdatum (nicht nach Favorisierungs-Zeitpunkt) — ein
/// persönlicher Konzertkalender soll zeigen, was als Nächstes ansteht, nicht
/// was zuletzt favorisiert wurde (Nutzerwunsch: "nach Datum... sammeln").
final _favoriteEventsProvider = FutureProvider.autoDispose<List<_FavoriteRow>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  // Auf denselben Provider hören, damit die Liste sich sofort aktualisiert,
  // sobald irgendwo ein Herz getoggelt wird — auch außerhalb dieses Screens.
  ref.watch(favoriteIdsProvider);

  final rows = await Supabase.instance.client
      .from('favorites')
      .select('''
          status,
          events(
            $homeEventColumns,
            event_participants(persons(full_name), ensembles(name)),
            event_works(works(title, composer:persons(full_name)))
          )
        ''')
      .eq('user_id', user.id);

  final items =
      (rows as List)
          .map(
            (r) => (
              event: r['events'] as Map<String, dynamic>?,
              status: FavoriteStatus.fromValue(r['status'] as String?),
            ),
          )
          .where((r) => r.event != null)
          .map((r) {
            final e = r.event!;
            final participants = (e['event_participants'] as List? ?? [])
                .expand(
                  (p) => [p['persons']?['full_name'], p['ensembles']?['name']],
                )
                .whereType<String>();
            final works = (e['event_works'] as List? ?? [])
                .expand(
                  (w) => [
                    w['works']?['title'],
                    w['works']?['composer']?['full_name'],
                  ],
                )
                .whereType<String>();
            final venueName = e['venues']?['name'] as String?;
            final searchText = [
              e['title'],
              venueName,
              ...participants,
              ...works,
            ].whereType<String>().join(' ').toLowerCase();

            return (
              event: HomeEventItem.fromRow(e),
              status: r.status,
              searchText: searchText,
            );
          })
          .toList()
        ..sort((a, b) {
          final aStart = a.event.startDateTime ?? DateTime(9999);
          final bStart = b.event.startDateTime ?? DateTime(9999);
          return aStart.compareTo(bStart);
        });
  return items;
});

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesTitle)),
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  l10n.favoritesSignInPrompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            )
          : ref
                .watch(_favoriteEventsProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      l10n.errorLoadingGeneric(e.toString()),
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                  data: (events) {
                    if (events.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            l10n.favoritesEmptyState,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      );
                    }
                    // Sammlung nach Datum/Künstler/Werk/Ort (Nutzerwunsch
                    // Punkt 1) — ein einziges Suchfeld über alle vier statt
                    // getrennter Filter-UI je Feld, da searchText bereits
                    // alle vier zusammenfasst.
                    final query = _query.trim().toLowerCase();
                    final filtered = query.isEmpty
                        ? events
                        : events
                              .where((r) => r.searchText.contains(query))
                              .toList();

                    // Zwei Gruppen statt einer flachen Liste (Nutzerwunsch:
                    // "als 'interessiert' oder 'besuche ich' markieren") —
                    // "Besuche ich" zuerst, das ist die verbindlichere
                    // Zusage und damit die relevantere Gruppe.
                    final attending = filtered
                        .where((r) => r.status == FavoriteStatus.attending)
                        .toList();
                    final interested = filtered
                        .where((r) => r.status == FavoriteStatus.interested)
                        .toList();

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screenPaddingMobile,
                            AppSpacing.sm,
                            AppSpacing.screenPaddingMobile,
                            0,
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              hintText: l10n.favoritesSearchHint,
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 20,
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: colors.backgroundSecondary,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.sm,
                                ),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      tooltip: l10n.searchClearTooltip,
                                      onPressed: () => setState(() {
                                        _searchController.clear();
                                        _query = '';
                                      }),
                                    ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    l10n.favoritesNoSearchResults(_query),
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.screenPaddingMobile,
                                    vertical: AppSpacing.md,
                                  ),
                                  children: [
                                    if (attending.isNotEmpty)
                                      _FavoriteGroup(
                                        title: l10n.favoritesStatusAttending,
                                        rows: attending,
                                        colors: colors,
                                      ),
                                    if (interested.isNotEmpty)
                                      _FavoriteGroup(
                                        title: l10n.favoritesStatusInterested,
                                        rows: interested,
                                        colors: colors,
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}

class _FavoriteGroup extends StatelessWidget {
  const _FavoriteGroup({
    required this.title,
    required this.rows,
    required this.colors,
  });

  final String title;
  final List<_FavoriteRow> rows;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${rows.length})',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          for (final row in rows) _FavoriteRowTile(row: row, colors: colors),
        ],
      ),
    );
  }
}

class _FavoriteRowTile extends ConsumerWidget {
  const _FavoriteRowTile({required this.row, required this.colors});

  final _FavoriteRow row;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final e = row.event;
    final isAttending = row.status == FavoriteStatus.attending;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: e.imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: e.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      GenreArtwork(genre: e.genre),
                  placeholder: (context, url) => GenreArtwork(genre: e.genre),
                )
              : GenreArtwork(genre: e.genre),
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Umschalt-Chip statt Untermenü — ein Antippen genügt, der Zustand
          // ist selbsterklärend an Farbe/Häkchen erkennbar.
          GestureDetector(
            onTap: () => FavoritesService.setStatus(
              ref,
              eventId: e.id,
              status: isAttending
                  ? FavoriteStatus.interested
                  : FavoriteStatus.attending,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isAttending
                    ? colors.success.withValues(alpha: 0.15)
                    : colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(999),
                border: isAttending
                    ? null
                    : Border.all(color: colors.separator),
              ),
              child: Text(
                isAttending
                    ? l10n.favoritesStatusAttending
                    : l10n.favoritesStatusInterested,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isAttending ? colors.success : colors.textSecondary,
                ),
              ),
            ),
          ),
          FavoriteButton(eventId: e.id, size: 20),
        ],
      ),
      onTap: () =>
          context.pushNamed('event-detail', pathParameters: {'slug': e.slug}),
    );
  }
}
