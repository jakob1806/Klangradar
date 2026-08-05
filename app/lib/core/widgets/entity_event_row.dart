import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

List<String> _monthAbbr(AppLocalizations l10n) => [
  l10n.monthJanShort,
  l10n.monthFebShort,
  l10n.monthMarShort,
  l10n.monthAprShort,
  l10n.monthMayShort,
  l10n.monthJunShort,
  l10n.monthJulShort,
  l10n.monthAugShort,
  l10n.monthSepShort,
  l10n.monthOctShort,
  l10n.monthNovShort,
  l10n.monthDecShort,
];

/// Eine Veranstaltungszeile für "Kommende/Vergangene Veranstaltungen" auf
/// Venue-/Personen-/Ensemble-Profilen — gemeinsam statt drei fast
/// identischer ListTile-Varianten je Screen (Nutzerwunsch: "kommende
/// veranstaltungen bei venues, personen oder ensembles sehen noch so
/// unsortiert und nicht schön entworfen aus... etwas geordneteres oder eher
/// praktischeres"). Datums-Badge links macht die Liste auf einen Blick
/// scanbar, statt Datum als Fließtext in der zweiten Zeile zu verstecken.
class EntityEventRow extends StatelessWidget {
  const EntityEventRow({
    super.key,
    required this.title,
    required this.slug,
    required this.start,
    this.subtitle,
  });

  final String title;
  final String slug;
  final DateTime? start;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/event/$slug'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DateBadge(start: start, colors: colors),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.start, required this.colors});

  final DateTime? start;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    if (start == null) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Icon(Icons.event_rounded, size: 20, color: colors.textTertiary),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.accentPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${start!.day}',
            style: TextStyle(
              color: colors.accentPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            _monthAbbr(AppLocalizations.of(context)!)[start!.month - 1],
            style: TextStyle(
              color: colors.accentPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
