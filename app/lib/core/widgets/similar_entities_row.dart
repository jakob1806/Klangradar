import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'genre_artwork.dart';

/// "Ähnliche Künstler:innen"/"Ähnliche Ensembles" (Phase D.2,
/// docs/09-feature-expansion-plan.md, Nutzerwunsch Punkt 7) — horizontale
/// Avatar-Reihe, gemeinsam für Personen- und Ensemble-Profile statt zweier
/// fast identischer Widgets.
class SimilarPersonsRow extends StatelessWidget {
  const SimilarPersonsRow({super.key, required this.entries});

  final List<dynamic> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) {
          final p = entries[i] as Map<String, dynamic>;
          return _EntityAvatar(
            slug: p['slug'] as String,
            name: p['full_name'] as String? ?? '',
            photoUrl: p['photo_url'] as String?,
            route: '/person',
          );
        },
      ),
    );
  }
}

class SimilarEnsemblesRow extends StatelessWidget {
  const SimilarEnsemblesRow({super.key, required this.entries});

  final List<dynamic> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) {
          final e = entries[i] as Map<String, dynamic>;
          return _EntityAvatar(
            slug: e['slug'] as String,
            name: e['name'] as String? ?? '',
            photoUrl: e['photo_url'] as String?,
            route: '/ensemble',
          );
        },
      ),
    );
  }
}

class _EntityAvatar extends StatelessWidget {
  const _EntityAvatar({
    required this.slug,
    required this.name,
    required this.photoUrl,
    required this.route,
  });

  final String slug;
  final String name;
  final String? photoUrl;
  final String route;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () => context.push('$route/$slug'),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: SizedBox(
                width: 56,
                height: 56,
                child: photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: photoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            const GenreArtwork(genre: EventGenre.kammermusik),
                        placeholder: (context, url) =>
                            const GenreArtwork(genre: EventGenre.kammermusik),
                      )
                    : const GenreArtwork(genre: EventGenre.kammermusik),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textPrimary, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}
