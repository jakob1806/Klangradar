import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../haptics.dart';
import '../interests/interests_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'detail_card.dart';

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

// Schwelle, ab der ein Suchfeld pro Kategorie eingeblendet wird —
// Nutzerfeedback: "Tab Interessen ist noch sehr unordentlich" (bei 116
// Ensembles/66 Venues unsortiert als eine große Chip-Wand ohne jede
// Filtermöglichkeit war das Auffinden einzelner Einträge unübersichtlich).
// Kleine Kategorien (Genres/Komponisten, hier meist <20) brauchen keine
// Suche, die würde nur zusätzliche UI ohne Nutzen hinzufügen.
const _kSearchThreshold = 12;

class InterestSection extends ConsumerStatefulWidget {
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
  ConsumerState<InterestSection> createState() => _InterestSectionState();
}

class _InterestSectionState extends ConsumerState<InterestSection> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    if (widget.options.isEmpty) return const SizedBox.shrink();

    // Ausgewählte zuerst (Nutzerfeedback: bei vielen Chips war schwer zu
    // sehen, was schon ausgewählt ist — reine Farbunterscheidung reicht bei
    // 100+ Chips nicht) — innerhalb beider Gruppen bleibt die vom Provider
    // gelieferte alphabetische Reihenfolge erhalten.
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? widget.options
        : widget.options
              .where((o) => o.label.toLowerCase().contains(normalizedQuery))
              .toList();
    final selectedFirst = [
      ...filtered.where((o) => widget.selectedIds.contains(o.id)),
      ...filtered.where((o) => !widget.selectedIds.contains(o.id)),
    ];

    return DetailCard(
      dividers: false,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (widget.selectedIds.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accentPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.interestsSelectedCount(widget.selectedIds.length),
                        style: TextStyle(
                          color: colors.accentPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (widget.options.length > _kSearchThreshold) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.interestsSearchHint,
                    hintStyle: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                    filled: true,
                    fillColor: colors.backgroundPrimary,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      borderSide: BorderSide(color: colors.separator),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      borderSide: BorderSide(color: colors.separator),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (selectedFirst.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    l10n.interestsNoResults,
                    style: TextStyle(color: colors.textTertiary, fontSize: 13),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in selectedFirst)
                      FilterChip(
                        label: Text(option.label),
                        selected: widget.selectedIds.contains(option.id),
                        onSelected: (_) {
                          // Interessen-Chip-Auswahl = "sehr leicht".
                          Haptics.light();
                          InterestsService.toggle(
                            ref,
                            category: widget.category,
                            id: option.id,
                            isSelected: widget.selectedIds.contains(option.id),
                          );
                        },
                        // Checkmark bewusst NICHT unterdrückt (siehe
                        // Barrierefreiheits-Audit): sonst wird "ausgewählt" nur
                        // über Hintergrund-/Rahmen-/Textfarbe signalisiert — für
                        // farbenblinde Nutzer:innen (accentPrimary ist ein
                        // Rotton) kaum von "nicht ausgewählt" zu unterscheiden.
                        selectedColor: colors.accentPrimary.withValues(
                          alpha: 0.16,
                        ),
                        backgroundColor: colors.backgroundSecondary,
                        side: BorderSide(
                          color: widget.selectedIds.contains(option.id)
                              ? colors.accentPrimary
                              : colors.separator,
                        ),
                        labelStyle: TextStyle(
                          color: widget.selectedIds.contains(option.id)
                              ? colors.accentPrimary
                              : colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
