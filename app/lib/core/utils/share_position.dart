import 'package:flutter/widgets.dart';

/// `share_plus` verlangt unter iOS zwingend ein nicht-leeres
/// `sharePositionOrigin` (iPad-Popover-Anker) — ohne das wirft
/// `Share.share`/`Share.shareXFiles` eine PlatformException. Bei einem
/// fire-and-forget-Aufruf (kein await/try-catch am Call-Site) blieb das
/// bisher unsichtbar: der Button "tat" einfach nichts (Nutzerfeedback zu
/// Kalender-/Teilen-Button auf der Event-Detailseite).
Rect sharePositionOriginFor(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.width > 0 && rect.height > 0) return rect;
  }
  // Fallback darf nicht Rect.zero sein.
  return Offset.zero & MediaQuery.sizeOf(context);
}
