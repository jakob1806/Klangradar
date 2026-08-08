import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../../l10n/generated/app_localizations.dart';

class CalendarSyncEvent {
  const CalendarSyncEvent({
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.location,
    this.url,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;
  final String? location;
  final String? url;
}

enum CalendarSyncOutcome { success, permissionDenied, error }

class CalendarSyncResult {
  const CalendarSyncResult(this.outcome, this.syncedCount, [this.message]);

  final CalendarSyncOutcome outcome;
  final int syncedCount;
  final String? message;
}

/// Legt einen dedizierten "Klangradar"-Kalender im Gerätekalender an und
/// hält ihn im Sync mit den anstehenden Favoriten. Da es der einzige Kalender
/// ist, den diese App befüllt, wird er vor jedem Sync geleert statt einzelne
/// Event-IDs zu tracken — einfacher als ein persistentes ID-Mapping und
/// trotzdem duplikatfrei bei wiederholtem Tap auf "Apple/Google Kalender".
class CalendarSyncService {
  const CalendarSyncService._();

  static const _calendarName = 'Klangradar';

  static Future<void> _ensureTimeZones() async {
    if (_timeZonesInitialized) return;
    tz_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }

  // getLocation() unten braucht die IANA-Zeitzonendatenbank des timezone-
  // Pakets, die anders als z.B. bei Firebase nicht automatisch initialisiert
  // wird — ohne diesen Aufruf wirft jeder Sync-Versuch eine
  // TimeZoneInitException. Lazy statt in main(), da nur dieser eine Screen
  // sie braucht.
  static bool _timeZonesInitialized = false;

  static Future<CalendarSyncResult> syncEvents(
    List<CalendarSyncEvent> events, {
    required AppLocalizations l10n,
  }) async {
    await _ensureTimeZones();

    final plugin = DeviceCalendarPlugin();

    var hasPermission = (await plugin.hasPermissions()).data ?? false;
    if (!hasPermission) {
      hasPermission = (await plugin.requestPermissions()).data ?? false;
    }
    if (!hasPermission) {
      return const CalendarSyncResult(CalendarSyncOutcome.permissionDenied, 0);
    }

    final calendarsResult = await plugin.retrieveCalendars();
    if (!calendarsResult.isSuccess) {
      return CalendarSyncResult(
        CalendarSyncOutcome.error,
        0,
        l10n.calendarSyncCalendarListError(
          calendarsResult.errors.map((e) => e.errorMessage).join('; '),
        ),
      );
    }
    Calendar? calendar;
    for (final c in calendarsResult.data ?? const <Calendar>[]) {
      if (c.name == _calendarName && c.isReadOnly != true) {
        calendar = c;
        break;
      }
    }
    if (calendar == null) {
      final created = await plugin.createCalendar(
        _calendarName,
        localAccountName: _calendarName,
      );
      if (!created.isSuccess || created.data == null) {
        return CalendarSyncResult(
          CalendarSyncOutcome.error,
          0,
          created.errors.map((e) => e.errorMessage).join('; '),
        );
      }
      calendar = Calendar(id: created.data);
    }

    final existing = await plugin.retrieveEvents(
      calendar.id,
      RetrieveEventsParams(startDate: DateTime(2000), endDate: DateTime(2100)),
    );
    if (!existing.isSuccess) {
      return CalendarSyncResult(
        CalendarSyncOutcome.error,
        0,
        l10n.calendarSyncExistingEventsError(
          existing.errors.map((e) => e.errorMessage).join('; '),
        ),
      );
    }
    for (final e in existing.data ?? const <Event>[]) {
      if (e.eventId == null) continue;
      final deleted = await plugin.deleteEvent(calendar.id, e.eventId);
      if (!deleted.isSuccess) {
        return CalendarSyncResult(
          CalendarSyncOutcome.error,
          0,
          l10n.calendarSyncDeleteOldEventError(
            deleted.errors.map((e) => e.errorMessage).join('; '),
          ),
        );
      }
    }

    final berlin = getLocation('Europe/Berlin');
    var synced = 0;
    var failed = 0;
    for (final e in events) {
      final result = await plugin.createOrUpdateEvent(
        Event(
          calendar.id,
          title: e.title,
          start: TZDateTime.from(e.start, berlin),
          end: TZDateTime.from(e.end, berlin),
          description: e.description,
          location: e.location,
          url: e.url != null ? Uri.tryParse(e.url!) : null,
        ),
      );
      if (result?.isSuccess ?? false) {
        synced++;
      } else {
        failed++;
      }
    }

    if (synced == 0 && events.isNotEmpty) {
      return CalendarSyncResult(
        CalendarSyncOutcome.error,
        0,
        l10n.calendarSyncNoneCreated,
      );
    }

    return CalendarSyncResult(
      CalendarSyncOutcome.success,
      synced,
      failed > 0 ? l10n.calendarSyncSomeFailed(failed) : null,
    );
  }
}
