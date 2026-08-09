import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'liquid_glass_surface.dart';

/// Zentrierter Glass-Dialog als Ersatz für `AlertDialog` an Stellen, die
/// bewusst im neuen Design stehen sollen (z.B. destruktive Bestätigungen).
Future<T?> showLiquidGlassDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<Widget> actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) =>
        LiquidGlassDialog(title: title, message: message, actions: actions),
  );
}

class LiquidGlassDialog extends StatelessWidget {
  const LiquidGlassDialog({
    required this.title,
    required this.actions,
    super.key,
    this.message,
  });

  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(AppRadius.card),
        blurSigma: AppGlassDepth.sheet,
        tintOpacity: 1.1,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.title3.copyWith(color: colors.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTypography.callout.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}
