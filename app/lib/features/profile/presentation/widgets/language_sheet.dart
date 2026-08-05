import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Sprachauswahl (Phase D.4, docs/09-feature-expansion-plan.md) — gleiches
/// Muster wie theme_mode_sheet.dart.
class LanguageSheet extends ConsumerWidget {
  const LanguageSheet({super.key, required this.current});

  final Locale? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (
        locale: null,
        label: l10n.profileLanguageSystem,
        icon: Icons.translate_rounded,
      ),
      (
        locale: const Locale('de'),
        label: l10n.profileLanguageGerman,
        icon: Icons.language_rounded,
      ),
      (
        locale: const Locale('en'),
        label: l10n.profileLanguageEnglish,
        icon: Icons.language_rounded,
      ),
    ];

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
              l10n.profileLanguage,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final option in options)
            ListTile(
              leading: Icon(option.icon, color: colors.textSecondary),
              title: Text(
                option.label,
                style: TextStyle(color: colors.textPrimary),
              ),
              trailing: option.locale?.languageCode == current?.languageCode
                  ? Icon(Icons.check_rounded, color: colors.accentPrimary)
                  : null,
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(option.locale);
                Navigator.of(context).pop();
              },
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
