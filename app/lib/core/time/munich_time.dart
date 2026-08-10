import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Einheitliche Veranstaltungszeitzone für alle Klangradar-Plattformen.
///
/// Supabase liefert Zeitpunkte als UTC. Für Anzeige, Tagesgruppierung und
/// Kalenderlogik werden sie unabhängig von der Gerätezeitzone in München
/// dargestellt; CET/CEST wird über die IANA-Datenbank automatisch gewählt.
abstract final class MunichTime {
  static const zoneName = 'Europe/Berlin';
  static bool _initialized = false;
  static late tz.Location _location;

  static void initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _location = tz.getLocation(zoneName);
    _initialized = true;
  }

  static tz.TZDateTime fromInstant(DateTime value) {
    initialize();
    return tz.TZDateTime.from(value.toUtc(), _location);
  }

  static tz.TZDateTime? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : fromInstant(parsed);
  }

  static tz.TZDateTime now() => fromInstant(DateTime.now());
}
