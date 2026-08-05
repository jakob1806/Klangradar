import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../interests/interests_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Die vier Interessen-Kategorien als Chip-Picker — gemeinsam genutzt von
/// InterestsScreen (Profil-Einstellung) und OnboardingScreen (Erststart).
class InterestPicker extends ConsumerWidget {
  const InterestPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genreOptionsProvider).valueOrNull ?? const [];
    final composers =
        ref.watch(composerOptionsProvider).valueOrNull ?? const [];
    final ensembles =
        ref.watch(ensembleOptionsProvider).valueOrNull ?? const [];
    final venues = ref.watch(venueOptionsProvider).valueOrNull ?? const [];
    final selected =
        ref.watch(userInterestsProvider).valueOrNull ?? UserInterests.empty;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InterestSection(
          title: l10n.interestCategoryGenres,
          options: genres,
          selectedIds: selected.genreIds,
          category: InterestCategory.genre,
        ),
        const SizedBox(height: AppSpacing.lg),
        InterestSection(
          title: l10n.interestCategoryComposers,
          options: composers,
          selectedIds: selected.personIds,
          category: InterestCategory.person,
        ),
        const SizedBox(height: AppSpacing.lg),
        InterestSection(
          title: l10n.interestCategoryEnsembles,
          options: ensembles,
          selectedIds: selected.ensembleIds,
          category: InterestCategory.ensemble,
        ),
        const SizedBox(height: AppSpacing.lg),
        InterestSection(
          title: l10n.interestCategoryVenues,
          options: venues,
          selectedIds: selected.venueIds,
          category: InterestCategory.venue,
        ),
      ],
    );
  }
}

class InterestSection extends ConsumerWidget {
  const InterestSection({
    super.key,
    required this.title,
    required this.options,
    required this.selectedIds,
    required this.category,
  });

  final String title;
  final List<InterestOption> options;
  final Set<String> selectedIds;
  final InterestCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    if (options.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option.label),
                selected: selectedIds.contains(option.id),
                onSelected: (_) => InterestsService.toggle(
                  ref,
                  category: category,
                  id: option.id,
                  isSelected: selectedIds.contains(option.id),
                ),
                // Checkmark bewusst NICHT unterdrückt (siehe
                // Barrierefreiheits-Audit): sonst wird "ausgewählt" nur über
                // Hintergrund-/Rahmen-/Textfarbe signalisiert — für
                // farbenblinde Nutzer:innen (accentPrimary ist ein Rotton)
                // kaum von "nicht ausgewählt" zu unterscheiden.
                selectedColor: colors.accentPrimary.withValues(alpha: 0.16),
                backgroundColor: colors.backgroundSecondary,
                side: BorderSide(
                  color: selectedIds.contains(option.id)
                      ? colors.accentPrimary
                      : colors.separator,
                ),
                labelStyle: TextStyle(
                  color: selectedIds.contains(option.id)
                      ? colors.accentPrimary
                      : colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
