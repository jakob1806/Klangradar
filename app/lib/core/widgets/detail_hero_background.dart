import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'genre_artwork.dart';

/// SliverAppBar-Hintergrund für Event-/Personen-/Ensemble-/Venue-Detail:
/// echtes Foto, wenn eins hinterlegt ist, sonst der bisherige
/// Genre-Platzhalter — beide Fälle mit demselben Verlaufs-Overlay für
/// lesbaren Text darüber. photo_url/image_urls existierten in allen vier
/// Tabellen von Anfang an, wurden aber nirgends gerendert.
class DetailHeroBackground extends StatelessWidget {
  const DetailHeroBackground({
    super.key,
    required this.photoUrl,
    required this.fallbackGenre,
    this.showGradient = true,
  });

  final String? photoUrl;
  final EventGenre fallbackGenre;

  /// EventDetail überlagert diesen Hintergrund mit einem eigenen,
  /// dreistufigen Verlauf (dunkler oben für die App-Bar-Icons, dunkler
  /// unten für das Status-Badge) statt des einfachen unteren Verlaufs hier.
  final bool showGradient;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photoUrl != null)
          CachedNetworkImage(
            imageUrl: photoUrl!,
            fit: BoxFit.cover,
            // Der feste Header ist oft schmaler/breiter als das Quellbild —
            // topCenter statt des Standard-center verhindert, dass Gesichter/
            // Motive nah am oberen Bildrand (z.B. Flyer-Portraits) abgeschnitten
            // werden.
            alignment: Alignment.topCenter,
            errorWidget: (context, url, error) =>
                GenreArtwork(genre: fallbackGenre),
            placeholder: (context, url) => GenreArtwork(genre: fallbackGenre),
          )
        else
          GenreArtwork(genre: fallbackGenre),
        if (showGradient)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xBF000000)],
                stops: [0.5, 1.0],
              ),
            ),
          ),
      ],
    );
  }
}
