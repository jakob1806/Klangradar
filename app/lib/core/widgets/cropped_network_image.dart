import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Zeigt einen redaktionell festgelegten Ausschnitt eines Bilds (siehe
/// Admin: components/entity-gallery/crop-tool.tsx — exakt dieselbe
/// Mathematik, sonst weicht die App-Darstellung von der Admin-Vorschau ab).
/// [crop] sind Anteile (0..1) des Originalbilds: (x, y) = obere linke Ecke,
/// (width, height) = Ausdehnung. `null` = kein redaktioneller Zuschnitt,
/// dann normales BoxFit.cover wie bisher.
///
/// Technik: das Bild wird auf `1/crop.width` × `1/crop.height` der
/// Zielgröße vergrößert (OverflowBox) und um `-crop.x`/`-crop.y` seiner
/// eigenen Größe verschoben (FractionalTranslation), sodass genau der
/// gewählte Ausschnitt im sichtbaren Bereich landet — Ableitung siehe
/// PR-Beschreibung "Bigger artist photo, thumbnails in search list, fix
/// db push CI"-Nachfolge-PR.
class CroppedNetworkImage extends StatelessWidget {
  const CroppedNetworkImage({
    super.key,
    required this.imageUrl,
    this.crop,
    this.errorWidget,
    this.placeholder,
  });

  final String imageUrl;
  final Rect? crop;
  final WidgetBuilder? errorWidget;
  final WidgetBuilder? placeholder;

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      // Nur relevant, wenn kein Zuschnitt gesetzt ist (Fallback unten) —
      // siehe DetailHeroBackground für die -0.6-Begründung
      // (Dynamic-Island/Notch-Freiraum).
      alignment: const Alignment(0, -0.6),
      errorWidget: errorWidget == null
          ? null
          : (context, url, error) => errorWidget!(context),
      placeholder: placeholder == null
          ? null
          : (context, url) => placeholder!(context),
    );

    final c = crop;
    if (c == null || c.width <= 0 || c.height <= 0) return image;

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return OverflowBox(
            maxWidth: w / c.width,
            maxHeight: h / c.height,
            alignment: Alignment.topLeft,
            child: FractionalTranslation(
              translation: Offset(-c.left, -c.top),
              child: SizedBox(
                width: w / c.width,
                height: h / c.height,
                child: image,
              ),
            ),
          );
        },
      ),
    );
  }
}
