import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'liquid_glass_surface.dart';

/// Kontrolliertes Glas-Overlay direkt AUF Bildern (Featured Event auf dem
/// Homescreen, Event-Header) — Vorgabe Abschnitt 2/4: "Informationen als
/// kontrolliertes Glas-Overlay" statt einer reinen Farbverlauf-Abdunklung.
/// Bewusst NUR am unteren Rand verankert (Alignment.bottomCenter via
/// `Positioned`, siehe Aufrufer) statt vollflächig — vermeidet exakt den
/// "Milchglas über allem"-Effekt, den die Vorgabe ausschließt.
class LiquidGlassEventOverlay extends StatelessWidget {
  const LiquidGlassEventOverlay({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(AppRadius.card),
        blurSigma: AppGlassDepth.control,
        onImage: true,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title3.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.footnote.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
