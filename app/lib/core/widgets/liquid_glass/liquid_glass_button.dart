import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'liquid_glass_surface.dart';

/// Primärer Glass-Button (gefüllte Tönung, Akzentfarbe) — reagiert auf
/// Pointer-Down statt erst auf Release (Skill-Referenz "Response: React to
/// pointer-down, not release") über `AnimatedScale` auf `TapDown`.
class LiquidGlassButton extends StatefulWidget {
  const LiquidGlassButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// true = gefüllte Akzentfläche (primäre Aktion), false = zurückhaltender
  /// Glass-Umriss (sekundäre Aktion).
  final bool filled;

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final disabled = widget.onPressed == null;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: disabled
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Opacity(
            opacity: disabled ? 0.4 : 1.0,
            child: LiquidGlassSurface(
              borderRadius: BorderRadius.circular(AppRadius.glassCapsule),
              blurSigma: AppGlassDepth.control,
              tintOpacity: widget.filled ? 2.2 : 0.7,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: colors.accentPrimary),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(
                    widget.label,
                    style: AppTypography.callout.copyWith(
                      fontWeight: FontWeight.w600,
                      color: widget.filled
                          ? colors.accentPrimary
                          : colors.textPrimary,
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

/// Runder Glass-Icon-Button (z.B. Profil-/Zurück-/Favoriten-Control über
/// Bildern) — mindestens 44×44pt Touch-Ziel (Vorgabe Abschnitt 3).
class LiquidGlassIconButton extends StatefulWidget {
  const LiquidGlassIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.semanticLabel,
    this.selected = false,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool selected;
  final double size;

  @override
  State<LiquidGlassIconButton> createState() => _LiquidGlassIconButtonState();
}

class _LiquidGlassIconButtonState extends State<LiquidGlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      selected: widget.selected,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: LiquidGlassSurface(
              borderRadius: BorderRadius.circular(widget.size / 2),
              blurSigma: AppGlassDepth.chip,
              tintOpacity: widget.selected ? 2.0 : 1.0,
              child: Icon(
                widget.icon,
                size: widget.size * 0.45,
                color: widget.selected
                    ? colors.accentPrimary
                    : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
