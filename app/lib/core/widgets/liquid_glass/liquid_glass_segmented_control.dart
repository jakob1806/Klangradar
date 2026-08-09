import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'liquid_glass_surface.dart';

/// Gläserner Segmented Control (z.B. Kalender-Ansicht Monat/Woche/Agenda) —
/// Vorgabe Abschnitt 5: "Kalender: native iOS-artige Auswahl mit gläsernen
/// Segmenten".
class LiquidGlassSegmentedControl<T> extends StatelessWidget {
  const LiquidGlassSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<({T value, String label})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
      blurSigma: AppGlassDepth.chip,
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            _Segment(
              label: segment.label,
              selected: segment.value == selected,
              onTap: () {
                if (segment.value != selected) {
                  HapticFeedback.selectionClick();
                  onChanged(segment.value);
                }
              },
              colors: colors,
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 38, minWidth: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.accentPrimary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.footnote.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.accentPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
