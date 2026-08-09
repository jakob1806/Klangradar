import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'liquid_glass_surface.dart';

/// Schwebendes Glas-Suchfeld — genutzt auf dem Homescreen und dem
/// Such-Screen (Vorgabe Abschnitt 5: "schwebendes Glass-Suchfeld").
class LiquidGlassSearchField extends StatelessWidget {
  const LiquidGlassSearchField({
    required this.hintText,
    super.key,
    this.controller,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.trailing,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LiquidGlassSurface(
      borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
      blurSigma: AppGlassDepth.control,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: colors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onTap: onTap,
                readOnly: readOnly,
                autofocus: autofocus,
                style: AppTypography.body.copyWith(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: AppTypography.body.copyWith(
                    color: colors.textTertiary,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
