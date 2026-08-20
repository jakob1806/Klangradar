import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../favorites/favorites_providers.dart';
import '../theme/app_colors.dart';

/// Herz-Button zum Favorisieren. Ohne Login zeigt ein Tap nur einen Hinweis —
/// Browsing bleibt account-frei, siehe docs/01-architecture.md §5.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({
    required this.eventId,
    this.size = 22,
    this.activeColor,
    this.inactiveColor,
    this.compact = false,
    super.key,
  });

  final String eventId;
  final double size;
  final Color? activeColor;
  final Color? inactiveColor;

  /// Ohne Standard-IconButton-Mindestgröße (48x48) — für Overlays auf kleinen
  /// Kartenbildern, z. B. [EventCard].
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteIdsProvider);
    final isFavorited = favorites.valueOrNull?.contains(eventId) ?? false;
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    Future<void> handleTap() async {
      if (ref.read(currentUserProvider) == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.favoriteSignInPrompt)));
        return;
      }
      await FavoritesService.toggle(
        ref,
        eventId: eventId,
        isFavorited: isFavorited,
      );
    }

    // compact wird ausschließlich als Overlay auf (dunklem) Artwork verwendet
    // (siehe EventCard) — Weiß als Default statt textTertiary, sonst zu
    // kontrastarm.
    final defaultInactive = compact ? Colors.white : colors.textTertiary;
    final icon = Icon(
      isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: size,
      color: isFavorited
          ? (activeColor ?? colors.accentPrimary)
          : (inactiveColor ?? defaultInactive),
    );
    final label = isFavorited
        ? l10n.favoriteLabelActive
        : l10n.favoriteLabelInactive;

    if (compact) {
      // Sichtbarer Kreis bleibt klein (Overlay auf Kartenbild), die Tap-
      // Fläche wird aber unsichtbar auf die 44x44-Mindestgröße aufgeweitet
      // (siehe Barrierefreiheits-Audit) statt den Kreis selbst zu vergrößern.
      return Semantics(
        button: true,
        label: label,
        onTap: handleTap,
        child: GestureDetector(
          onTap: handleTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0x59000000),
                  shape: BoxShape.circle,
                ),
                child: icon,
              ),
            ),
          ),
        ),
      );
    }

    return IconButton(icon: icon, tooltip: label, onPressed: handleTap);
  }
}
