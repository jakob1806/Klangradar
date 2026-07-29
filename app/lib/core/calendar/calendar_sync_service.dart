import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/data/latest.dart' as tz_data;

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

/// Legt einen dedizierten "Klassik München"-Kalender im Gerätekalender an und
/// hält ihn im Sync mit den anstehenden Favoriten. Da es der einzige Kalender
/// ist, den diese App befüllt, wird er vor jedem Sync geleert statt einzelne
/// Event-IDs zu tracken — einfacher als ein persistentes ID-Mapping und
/// trotzdem duplikatfrei bei wiederholtem Tap auf "Apple/Google Kalender".
class CalendarSyncService {
  const CalendarSyncService._();

  static const _calendarName = 'Klassik München';

  static Future<void> _ensureTimeZones() async {
    if (_timeZonesInitialized) return;
    tz_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }

  /// Fragt Kalenderberechtigung an und liefert alle beschreibbaren
  /// Gerätekalender (z.B. "Privat"/"Arbeit"/ein Google-Konto) — Grundlage
  /// für die Kalenderauswahl beim Einzel-Event-Import (Nutzeranfrage:
  /// "auswahl der kalenderkategorie beachten"). Gibt null zurück, wenn die
  /// Berechtigung verweigert wurde.
  static Future<List<Calendar>?> requestWritableCalendars() async {
    await _ensureTimeZones();
    final plugin = DeviceCalendarPlugin();

    var hasPermission = (await plugin.hasPermissions()).data ?? false;
    if (!hasPermission) {
      hasPermission = (await plugin.requestPermissions()).data ?? false;
    }
    if (!hasPermission) return null;

    final result = await plugin.retrieveCalendars();
    if (!result.isSuccess) return const [];
    return (result.data ?? const <Calendar>[])
        .where((c) => c.isReadOnly != true)
        .toList();
  }

  /// Trägt EIN Event in den ausgewählten Gerätekalender ein — anders als
  /// [syncEvents] (Bulk-Abgleich für den Favoriten-Sync-Sheet, leert vorher
  /// den ganzen "Klassik München"-Kalender) wird hier nichts gelöscht, das
  /// würde bei einem einzelnen Ad-hoc-"Zum Kalender hinzufügen"-Tap
  /// bestehende Einträge im gewählten Kalender zerstören.
  ///
  /// Prüft vorher auf einen bereits vorhandenen Eintrag mit demselben Titel
  /// zur selben Startzeit und aktualisiert diesen statt einen neuen
  /// anzulegen — sonst erzeugt ein zweiter Tap auf denselben Button (z.B.
  /// aus Versehen) ein Duplikat im Kalender der Nutzerin, live beim Testen
  /// beobachtet.
  static Future<CalendarSyncResult> addEventToCalendar({
    required CalendarSyncEvent event,
    required String calendarId,
  }) async {
    await _ensureTimeZones();
    final plugin = DeviceCalendarPlugin();
    final berlin = getLocation('Europe/Berlin');
    final start = TZDateTime.from(event.start, berlin);
    final end = TZDateTime.from(event.end, berlin);

    String? existingEventId;
    final existing = await plugin.retrieveEvents(
      calendarId,
      RetrieveEventsParams(
        startDate: event.start.subtract(const Duration(minutes: 1)),
        endDate: event.start.add(const Duration(minutes: 1)),
      ),
    );
    if (existing.isSuccess) {
      for (final e in existing.data ?? const <Event>[]) {
        if (e.title == event.title) {
          existingEventId = e.eventId;
          break;
        }
      }
    }

    final result = await plugin.createOrUpdateEvent(
      Event(
        calendarId,
        eventId: existingEventId,
        title: event.title,
        start: start,
        end: end,
        description: event.description,
        location: event.location,
        url: event.url != null ? Uri.tryParse(event.url!) : null,
      ),
    );

    if (result?.isSuccess ?? false) {
      return const CalendarSyncResult(CalendarSyncOutcome.success, 1);
    }
    return CalendarSyncResult(
      CalendarSyncOutcome.error,
      0,
      result?.errors.map((e) => e.errorMessage).join('; '),
    );
  }

  // getLocation() unten braucht die IANA-Zeitzonendatenbank des timezone-
  // Pakets, die anders als z.B. bei Firebase nicht automatisch initialisiert
  // wird — ohne diesen Aufruf wirft jeder Sync-Versuch eine
  // TimeZoneInitException. Lazy statt in main(), da nur dieser eine Screen
  // sie braucht.
  static bool _timeZonesInitialized = false;

  static Future<CalendarSyncResult> syncEvents(
    List<CalendarSyncEvent> events,
  ) async {
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
        'Kalenderliste konnte nicht gelesen werden: '
        '${calendarsResult.errors.map((e) => e.errorMessage).join('; ')}',
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
        'Bestehende Kalendereinträge konnten nicht gelesen werden — '
        'Abbruch, um keine Duplikate zu erzeugen: '
        '${existing.errors.map((e) => e.errorMessage).join('; ')}',
      );
    }
    for (final e in existing.data ?? const <Event>[]) {
      if (e.eventId == null) continue;
      final deleted = await plugin.deleteEvent(calendar.id, e.eventId);
      if (!deleted.isSuccess) {
        return CalendarSyncResult(
          CalendarSyncOutcome.error,
          0,
          'Alter Kalendereintrag konnte nicht entfernt werden — Abbruch, '
          'um keine Duplikate zu erzeugen: '
          '${deleted.errors.map((e) => e.errorMessage).join('; ')}',
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
      return const CalendarSyncResult(
        CalendarSyncOutcome.error,
        0,
        'Keine Veranstaltung konnte eingetragen werden.',
      );
    }

    return CalendarSyncResult(
      CalendarSyncOutcome.success,
      synced,
      failed > 0
          ? '$failed Veranstaltung(en) konnten nicht eingetragen werden.'
          : null,
    );
  }
}
