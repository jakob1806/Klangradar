import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'liquid_glass_surface.dart';

class LiquidGlassNavDestination {
  const LiquidGlassNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Schwebende Glaskapsel-Tabbar (ersetzt Materials `NavigationBar` in
/// `app_shell.dart`) — Nutzervorgabe Abschnitt 3: "schwebende Glaskapsel
/// über dem Inhalt", Inhalt läuft edge-to-edge dahinter (der Scaffold, der
/// dies einbindet, muss `extendBody: true` setzen — bereits der Fall in
/// `app_shell.dart`). Touch-Ziele sind durch `minHeight` je Tab mindestens
/// 44pt hoch, unabhängig von der Kapselhöhe.
class LiquidGlassNavigationBar extends StatelessWidget {
  const LiquidGlassNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<LiquidGlassNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        bottomInset > 0 ? bottomInset * 0.5 : AppSpacing.sm,
      ),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
        blurSigma: AppGlassDepth.navigation,
        tintOpacity: 1.3,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < destinations.length; i++)
              _NavTab(
                destination: destinations[i],
                selected: i == selectedIndex,
                onTap: () {
                  if (i != selectedIndex) HapticFeedback.selectionClick();
                  onSelected(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final LiquidGlassNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? colors.accentPrimary.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 22,
                    color: selected
                        ? colors.accentPrimary
                        : colors.textTertiary,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.label,
                    style: AppTypography.caption.copyWith(
                      color: selected
                          ? colors.accentPrimary
                          : colors.textTertiary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
