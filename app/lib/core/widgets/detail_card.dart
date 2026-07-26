import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Gemeinsamer Karten-Container für gruppierte Listen auf Detailseiten
/// (Programm, Besetzung, Säle, ...) — Phase 6: "Programm/Besetzung als
/// saubere strukturierte Listen/Karten" statt loser, nur durch Abstand
/// getrennter Zeilen. Bewusst schlicht (Hintergrund + dezenter Rand, kein
/// Schatten) — docs/04-design-system.md erlaubt Elevation-Schatten nur für
/// Modale/Popover, Karten in Listen bleiben flach.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.children, this.dividers = true});

  final List<Widget> children;

  /// Trennlinie zwischen Kindern — an für homogene Listen (Programm-
  /// Zeilen), aus wenn ein Kind selbst schon vertikalen Raum/Trennung
  /// mitbringt.
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final items = dividers
        ? [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: colors.separator),
              children[i],
            ],
          ]
        : children;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppSpacing.lg),
        border: Border.all(color: colors.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      ),
    );
  }
}
