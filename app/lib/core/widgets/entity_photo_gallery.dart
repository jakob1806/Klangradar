import 'package:flutter/material.dart';

import '../gallery/entity_gallery_providers.dart';
import 'cropped_network_image.dart';
import 'genre_artwork.dart';

/// SliverAppBar-Hintergrund für Personen/Ensembles mit mehr als einem
/// freigegebenen Galerie-Bild: durchwischbar (Nutzerwunsch: "zwischen
/// mehreren hin und herwischen"), jedes Bild im redaktionell festgelegten
/// Querformat-Zuschnitt (siehe CroppedNetworkImage). Bei nur einem Bild
/// entfällt die PageView bewusst nicht — Konsistenz (Punktindikator fehlt
/// dann einfach, da nur 1 Punkt keinen Sinn ergibt) ist wichtiger als eine
/// Sonderfall-Verzweigung zwischen 1 und >1 Bildern.
class EntityPhotoGallery extends StatefulWidget {
  const EntityPhotoGallery({
    super.key,
    required this.images,
    required this.fallbackGenre,
    this.showGradient = true,
  });

  /// Muss nicht-leer sein — der Aufrufer entscheidet anhand der Provider-
  /// Daten, ob DetailHeroBackground (kein Galerie-Bild) oder dieses Widget
  /// gerendert wird.
  final List<GalleryImage> images;
  final EventGenre fallbackGenre;
  final bool showGradient;

  @override
  State<EntityPhotoGallery> createState() => _EntityPhotoGalleryState();
}

class _EntityPhotoGalleryState extends State<EntityPhotoGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (context, i) {
            final image = widget.images[i];
            return CroppedNetworkImage(
              imageUrl: image.url,
              crop: image.crop,
              errorWidget: (context) =>
                  GenreArtwork(genre: widget.fallbackGenre),
              placeholder: (context) =>
                  GenreArtwork(genre: widget.fallbackGenre),
            );
          },
        ),
        if (widget.showGradient)
          IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Verlauf oben UND unten (nicht nur unten wie bisher) —
                  // siehe DetailHeroBackground für die Begründung
                  // (Status-Bar-/Dynamic-Island-Lesbarkeit).
                  colors: [
                    Color(0x59000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xBF000000),
                  ],
                  stops: [0.0, 0.2, 0.5, 1.0],
                ),
              ),
            ),
          ),
        if (widget.images.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: i == _page ? 14 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: i == _page ? 0.95 : 0.5,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
