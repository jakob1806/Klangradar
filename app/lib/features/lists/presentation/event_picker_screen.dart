import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/application/home_providers.dart';
import '../application/event_lists_providers.dart';

final _upcomingEventsForPickerProvider =
    FutureProvider.autoDispose<List<HomeEventItem>>((ref) async {
      final rows = await Supabase.instance.client
          .from('events')
          .select(homeEventColumns)
          .eq('status', 'scheduled')
          .gte('start_datetime', MunichTime.now().toIso8601String())
          .order('start_datetime', ascending: true)
          .limit(300);
      return (rows as List)
          .map((r) => HomeEventItem.fromRow(r as Map<String, dynamic>))
          .toList();
    });

/// Nutzeranfrage: fehlender Button, um ausgewählte Veranstaltungen zu einer
/// Liste zu speichern — Pendant zu iOS' EventListPicker (UserEventListsView.
/// swift), "Fertig" oben rechts speichert die Auswahl per
/// [EventListsService.replaceEvents].
class EventPickerScreen extends ConsumerStatefulWidget {
  const EventPickerScreen({
    required this.listId,
    required this.currentEventIds,
    super.key,
  });

  final String listId;
  final Set<String> currentEventIds;

  @override
  ConsumerState<EventPickerScreen> createState() => _EventPickerScreenState();
}

class _EventPickerScreenState extends ConsumerState<EventPickerScreen> {
  late Set<String> _selected;
  final _searchController = TextEditingController();
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = Set.of(widget.currentEventIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Finales Speichern der Listen-Auswahl = Bestätigung.
    Haptics.confirm();
    await EventListsService.replaceEvents(
      ref,
      listId: widget.listId,
      selected: _selected,
      previous: widget.currentEventIds,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final eventsAsync = ref.watch(_upcomingEventsForPickerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myListsPickerTitle),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              l10n.myListsSave,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _saving ? colors.textTertiary : colors.accentPrimary,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPaddingMobile,
              AppSpacing.sm,
              AppSpacing.screenPaddingMobile,
              0,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: l10n.myListsPickerSearchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: colors.backgroundSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: eventsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  l10n.errorLoadingGeneric(e.toString()),
                  style: TextStyle(color: colors.error),
                ),
              ),
              data: (events) {
                final query = _query.trim().toLowerCase();
                final filtered = query.isEmpty
                    ? events
                    : events
                          .where(
                            (e) =>
                                e.title.toLowerCase().contains(query) ||
                                e.venueAndTime.toLowerCase().contains(query),
                          )
                          .toList();

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final e = filtered[index];
                    final isSelected = _selected.contains(e.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(e.id);
                        } else {
                          _selected.remove(e.id);
                        }
                      }),
                      title: Text(
                        e.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        e.venueAndTime,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
