import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'favorite_button.dart';
import 'genre_artwork.dart';

/// Karten-Widget für Event-Listen (Home-Sektionen, Suchergebnisse, Favoriten).
/// Bild trägt die Emotion, Metadaten bleiben knapp — siehe
/// docs/04-design-system.md, §4 „EventCard".
class EventCard extends StatelessWidget {
  const EventCard({
    required this.eventId,
    required this.title,
    required this.venueAndTime,
    required this.genre,
    this.imageUrl,
    this.badgeLabel,
    this.onTap,
    this.width = 150,
    super.key,
  });

  final String eventId;
  final String title;
  final String venueAndTime;
  final EventGenre genre;
  final String? imageUrl;
  final String? badgeLabel;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: width,
      // Ein Semantics-Knoten für Titel+Venue+Zeit+Badge, damit Screen-Reader
      // eine zusammenhängende Ansage statt einzelner Textfragmente bekommen
      // (siehe Barrierefreiheits-Audit). Die darunterliegenden Text-Widgets
      // werden per ExcludeSemantics stummgeschaltet, der FavoriteButton
      // BLEIBT als eigener, separat fokussierbarer Knoten erreichbar.
      child: Semantics(
        button: true,
        label: badgeLabel != null
            ? '$title, $venueAndTime, $badgeLabel'
            : '$title, $venueAndTime',
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 2,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => GenreArtwork(
                          genre: genre,
                          borderRadius: BorderRadius.circular(
                            AppRadius.cardImage,
                          ),
                        ),
                        placeholder: (context, url) => GenreArtwork(
                          genre: genre,
                          borderRadius: BorderRadius.circular(
                            AppRadius.cardImage,
                          ),
                        ),
                        imageBuilder: (context, imageProvider) => ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppRadius.cardImage,
                          ),
                          child: Image(image: imageProvider, fit: BoxFit.cover),
                        ),
                      )
                    else
                      GenreArtwork(
                        genre: genre,
                        borderRadius: BorderRadius.circular(
                          AppRadius.cardImage,
                        ),
                      ),
                    if (badgeLabel != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: ExcludeSemantics(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accentSecondary.withValues(
                                alpha: 0.9,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badgeLabel!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                // Feste dunkle Farbe statt colors.
                                // backgroundPrimary: die war im Light-Theme
                                // (fast weiß) auf dem goldenen Badge-
                                // Hintergrund nur 2.15:1 Kontrast — fest
                                // dunkel funktioniert in beiden Themes, weil
                                // accentSecondary in Light UND Dark ein
                                // mittelheller Goldton ist.
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: FavoriteButton(
                        eventId: eventId,
                        size: 15,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ExcludeSemantics(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              ExcludeSemantics(
                child: Text(
                  venueAndTime,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
