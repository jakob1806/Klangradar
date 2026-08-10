import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';
import '../events/event_filters.dart';
import '../events/filtered_events_providers.dart';
import '../interests/interests_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../time/munich_time.dart';

/// "FilterSheet (Modal, von überall aufrufbar)" laut
/// docs/05-navigation-structure.md — ein einziger Einstiegspunkt statt
/// screen-eigener Filter-UI, damit Suche, Karte etc. dieselbe Sheet nutzen
/// können, sobald sie Filter brauchen.
Future<void> showEventFilterSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _EventFilterSheet(),
  );
}

Map<double?, String> _priceLabels(AppLocalizations l10n) => {
  null: l10n.filterSheetPriceAll,
  20.0: l10n.filterSheetPriceUpTo('20'),
  50.0: l10n.filterSheetPriceUpTo('50'),
};

Map<double?, String> _distanceLabels(AppLocalizations l10n) => {
  null: l10n.filterSheetDistanceAny,
  1.0: l10n.filterSheetDistanceKm('1'),
  5.0: l10n.filterSheetDistanceKm('5'),
  10.0: l10n.filterSheetDistanceKm('10'),
};

class _EventFilterSheet extends ConsumerStatefulWidget {
  const _EventFilterSheet();

  @override
  ConsumerState<_EventFilterSheet> createState() => _EventFilterSheetState();
}

class _EventFilterSheetState extends ConsumerState<_EventFilterSheet> {
  DateTimeRange? _dateRange;
  late Set<String> _genreIds;
  double? _maxPrice;
  bool _accessibleOnly = false;
  bool _openAirOnly = false;
  double? _maxDistanceKm;

  @override
  void initState() {
    super.initState();
    final current = ref.read(eventFiltersProvider);
    _dateRange = current.dateRange;
    _genreIds = Set.of(current.genreIds);
    _maxPrice = current.maxPrice;
    _accessibleOnly = current.accessibleOnly;
    _openAirOnly = current.openAirOnly;
    _maxDistanceKm = current.maxDistanceKm;
  }

  Future<void> _pickDateRange() async {
    final now = MunichTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      locale: Localizations.localeOf(context),
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  void _apply() {
    ref.read(eventFiltersProvider.notifier).state = EventFilters(
      dateRange: _dateRange,
      genreIds: _genreIds,
      maxPrice: _maxPrice,
      accessibleOnly: _accessibleOnly,
      openAirOnly: _openAirOnly,
      maxDistanceKm: _maxDistanceKm,
    );
    Navigator.of(context).pop();
  }

  void _reset() {
    setState(() {
      _dateRange = null;
      _genreIds = {};
      _maxPrice = null;
      _accessibleOnly = false;
      _openAirOnly = false;
      _maxDistanceKm = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final genres = ref.watch(genreOptionsProvider).valueOrNull ?? const [];
    final dateFormat = DateFormat('d.M.', locale);
    final dateLabel = _dateRange == null
        ? l10n.filterSheetDateAny
        : '${dateFormat.format(_dateRange!.start)} – ${dateFormat.format(_dateRange!.end)}';

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.screenPaddingMobile),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.filterSheetTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: _reset,
                  child: Text(l10n.filterSheetReset),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.filterSheetDate,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(dateLabel),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.filterSheetGenre,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in genres)
                  FilterChip(
                    label: Text(genre.label),
                    selected: _genreIds.contains(genre.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _genreIds.add(genre.id);
                      } else {
                        _genreIds.remove(genre.id);
                      }
                    }),
                    // Checkmark bewusst NICHT unterdrückt, siehe
                    // Barrierefreiheits-Audit / interest_picker.dart.
                    selectedColor: colors.accentPrimary.withValues(alpha: 0.16),
                    labelStyle: TextStyle(
                      color: _genreIds.contains(genre.id)
                          ? colors.accentPrimary
                          : colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.filterSheetPrice,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _priceLabels(l10n).entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _maxPrice == entry.key,
                    onSelected: (_) => setState(() => _maxPrice = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.filterSheetDistance,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.filterSheetDistanceHint,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _distanceLabels(l10n).entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _maxDistanceKm == entry.key,
                    onSelected: (_) =>
                        setState(() => _maxDistanceKm = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.filterSheetAccessible),
              value: _accessibleOnly,
              activeThumbColor: colors.accentPrimary,
              onChanged: (v) => setState(() => _accessibleOnly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.filterSheetOpenAir),
              value: _openAirOnly,
              activeThumbColor: colors.accentPrimary,
              onChanged: (v) => setState(() => _openAirOnly = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _apply,
                child: Text(l10n.filterSheetApply),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
