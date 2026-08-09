import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'liquid_glass_surface.dart';

/// Bottom-Sheet mit stärkerem Blur als normale Controls (Vorgabe Abschnitt
/// 5: "Sheets: stärkeres Blur als normale Controls, klare Drag-Handle- und
/// Safe-Area-Behandlung"). `showLiquidGlassSheet` ist der empfohlene
/// Einstiegspunkt, damit Drag-Handle/Safe-Area nicht pro Aufrufstelle neu
/// gebaut werden.
Future<T?> showLiquidGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (context) => LiquidGlassSheet(child: builder(context)),
  );
}

class LiquidGlassSheet extends StatelessWidget {
  const LiquidGlassSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: LiquidGlassSurface(
        borderRadius: const BorderRadius.all(
          Radius.circular(AppRadius.bottomSheet),
        ),
        blurSigma: AppGlassDepth.sheet,
        tintOpacity: 1.1,
        child: Padding(
          padding: EdgeInsets.only(
            top: AppSpacing.sm,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: bottomInset + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
