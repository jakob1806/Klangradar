import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../l10n/generated/app_localizations.dart';

class ThemeModeSheet extends ConsumerWidget {
  const ThemeModeSheet({super.key, required this.current});

  final ThemeMode current;

  static List<({ThemeMode mode, String label, IconData icon})> _options(
    AppLocalizations l10n,
  ) => [
    (
      mode: ThemeMode.system,
      label: l10n.themeModeSystem,
      icon: Icons.brightness_auto_rounded,
    ),
    (
      mode: ThemeMode.light,
      label: l10n.themeModeLight,
      icon: Icons.light_mode_rounded,
    ),
    (
      mode: ThemeMode.dark,
      label: l10n.themeModeDark,
      icon: Icons.dark_mode_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPaddingMobile,
              AppSpacing.lg,
              AppSpacing.screenPaddingMobile,
              AppSpacing.sm,
            ),
            child: Text(
              l10n.themeModeSheetTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final option in _options(l10n))
            ListTile(
              leading: Icon(option.icon, color: colors.textSecondary),
              title: Text(
                option.label,
                style: TextStyle(color: colors.textPrimary),
              ),
              trailing: option.mode == current
                  ? Icon(Icons.check_rounded, color: colors.accentPrimary)
                  : null,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(option.mode);
                Navigator.of(context).pop();
              },
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
