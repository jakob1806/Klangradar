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
import '../../home/application/home_providers.dart';

final _favoriteEventsProvider = FutureProvider.autoDispose<List<HomeEventItem>>(
  (ref) async {
    final user = ref.watch(currentUserProvider);
    if (user == null) return [];

    // Auf denselben Provider hören, damit die Liste sich sofort aktualisiert,
    // sobald irgendwo ein Herz getoggelt wird — auch außerhalb dieses Screens.
    ref.watch(favoriteIdsProvider);

    final rows = await Supabase.instance.client
        .from('favorites')
        .select('created_at, events($homeEventColumns)')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => r['events'])
        .whereType<Map<String, dynamic>>()
        .map(HomeEventItem.fromRow)
        .toList();
  },
);

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Favoriten')),
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Bitte im Profil-Tab anmelden, um Favoriten zu sehen.',
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
                      'Fehler beim Laden: $e',
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                  data: (events) {
                    if (events.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'Noch keine Favoriten. Tippe auf das Herz bei einer Veranstaltung, um sie hier zu sammeln.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPaddingMobile,
                        vertical: AppSpacing.md,
                      ),
                      itemCount: events.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: colors.separator, height: 1),
                      itemBuilder: (context, i) {
                        final e = events[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
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
                                      placeholder: (context, url) =>
                                          GenreArtwork(genre: e.genre),
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
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                          trailing: FavoriteButton(eventId: e.id, size: 20),
                          onTap: () => context.push('/event/${e.slug}'),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
