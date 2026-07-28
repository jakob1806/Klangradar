import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/calendar/calendar_sync_service.dart';
import '../../../../core/calendar/ics_export.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../application/calendar_providers.dart';

/// docs/05-navigation-structure.md, Kalender-Tab: "Sync-Optionen (Sheet):
/// Apple Kalender, Google Kalender, ICS-Export". Beide nativen Store-APIs
/// (EventKit/CalendarContract) sind pro Plattform exklusiv, daher zeigt das
/// Sheet nur die für das laufende Gerät zutreffende Option statt beider
/// Labels gleichzeitig — plus ICS-Export, das auf beiden Plattformen läuft.
class CalendarSyncSheet extends ConsumerStatefulWidget {
  const CalendarSyncSheet({super.key});

  @override
  ConsumerState<CalendarSyncSheet> createState() => _CalendarSyncSheetState();
}

class _CalendarSyncSheetState extends ConsumerState<CalendarSyncSheet> {
  bool _busy = false;

  Future<void> _syncToDeviceCalendar(List<SyncableEvent> events) async {
    setState(() => _busy = true);
    try {
      final result = await CalendarSyncService.syncEvents([
        for (final e in events)
          CalendarSyncEvent(
            title: e.title,
            start: e.start,
            end: e.end,
            description: e.description,
            location: e.location,
            url: e.url,
          ),
      ]);
      if (!mounted) return;

      final message = switch (result.outcome) {
        CalendarSyncOutcome.success =>
          '${result.syncedCount} Veranstaltung${result.syncedCount == 1 ? '' : 'en'} synchronisiert.'
              '${result.message != null ? ' ${result.message}' : ''}',
        CalendarSyncOutcome.permissionDenied =>
          'Kalenderzugriff verweigert. Bitte in den Systemeinstellungen erlauben.',
        CalendarSyncOutcome.error =>
          'Synchronisierung fehlgeschlagen${result.message != null ? ': ${result.message}' : '.'}',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (result.outcome == CalendarSyncOutcome.success) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synchronisierung fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportIcs(List<SyncableEvent> events) async {
    setState(() => _busy = true);
    try {
      await IcsExport.shareMultiple(
        context: context,
        events: [
          for (final e in events)
            IcsEventInput(
              uid: e.id,
              title: e.title,
              start: e.start,
              end: e.end,
              description: e.description,
              location: e.location,
              url: e.url,
            ),
        ],
        fileName: 'klassik-muenchen-favoriten.ics',
        subject: 'Meine Klassik München Favoriten',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(upcomingFavoriteEventsProvider);
    final isIOS = !kIsWeb && Platform.isIOS;
    final isAndroid = !kIsWeb && Platform.isAndroid;

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
              4,
            ),
            child: Text(
              'Kalender synchronisieren',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPaddingMobile,
              0,
              AppSpacing.screenPaddingMobile,
              AppSpacing.sm,
            ),
            child: Text(
              'Trägt deine anstehenden Favoriten in deinen Kalender ein.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'Fehler beim Laden: $e',
                style: TextStyle(color: colors.error),
              ),
            ),
            data: (events) {
              if (events.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPaddingMobile,
                    0,
                    AppSpacing.screenPaddingMobile,
                    AppSpacing.xl,
                  ),
                  child: Text(
                    'Noch keine anstehenden Favoriten. Favorisiere Veranstaltungen, um sie hier zu synchronisieren.',
                    style: TextStyle(color: colors.textTertiary, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: [
                  if (isIOS || isAndroid)
                    ListTile(
                      enabled: !_busy,
                      leading: Icon(
                        Icons.calendar_month_rounded,
                        color: colors.textSecondary,
                      ),
                      title: Text(
                        isIOS ? 'Apple Kalender' : 'Google Kalender',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      subtitle: Text(
                        'Direkt in deinen Gerätekalender eintragen',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                      onTap: _busy ? null : () => _syncToDeviceCalendar(events),
                    ),
                  ListTile(
                    enabled: !_busy,
                    leading: Icon(
                      Icons.ios_share_rounded,
                      color: colors.textSecondary,
                    ),
                    title: Text(
                      'ICS-Export',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      'Als Datei teilen oder speichern',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    onTap: _busy ? null : () => _exportIcs(events),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPaddingMobile,
                        vertical: AppSpacing.sm,
                      ),
                      child: LinearProgressIndicator(),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
