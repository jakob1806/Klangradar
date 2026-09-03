import 'package:flutter/services.dart';

/// Zentrale Haptik-Utility der App — bündelt alle taktilen Rückmeldungen in
/// drei Intensitätsstufen plus zwei Sonderfällen, analog zum parallel
/// gebauten Haptik-System der nativen iOS-App (siehe ios-native/, dort nicht
/// angerührt). Ziel: konsistentes, nicht-nervöses Feedback — sehr leichte
/// Aktionen (Auswahl, Toggle) fühlen sich anders an als bestätigende
/// Aktionen (Folgen, Speichern) und deutliche Meilensteine (Registrierung
/// abgeschlossen, Termin im Kalender).
///
/// Mapping-Entscheidung (auf die von Flutter bereitgestellten
/// `HapticFeedback`-Methoden):
/// - [light]: `selectionClick()` — kürzester, unaufdringlichster Impuls;
///   für Auswahl/Toggle/Umschalten (Interessen-Chip, Filter-Toggle, Stadt
///   antippen zum Vorschauen, Kalendertag wechseln).
/// - [confirm]: `mediumImpact()` — spürbar stärker als `light`, markiert
///   eine abgeschlossene Nutzeraktion (Folgen, Favorisieren, Erinnerung
///   aktivieren, Liste anlegen/Event hinzufügen, Stadt bestätigen,
///   Interessen-Mindestanzahl erreicht).
/// - [strong]: `heavyImpact()` — deutlichster Impuls, reserviert für
///   seltene, bedeutsame Erfolgsmomente (Registrierung abgeschlossen,
///   Termin erfolgreich im Kalender, Check-in, Meilensteine).
/// - [soft]: `lightImpact()` — schwächer als [confirm], für Aktionen, die
///   bewusst zurückhaltender wirken sollen als ihr Gegenstück (Entfolgen
///   statt Folgen, sanftes Ausblenden/"Nicht interessiert" eines Events).
/// - [warning]: `mediumImpact()` — bewusst kein eigener "Vibrate"-Modus
///   (Flutter/iOS bieten dafür keine granularere Stufe als `mediumImpact`
///   ohne externe Pakete); genutzt für sehr zurückhaltende Warnhinweise,
///   z. B. beim aktiven Öffnen einer Absage-/Programmänderungs-Meldung —
///   NICHT beim bloßen Laden/Anzeigen der Daten.
class Haptics {
  const Haptics._();

  /// Sehr leicht: Auswahl, Filter-Toggle, Stadt antippen (Vorschau),
  /// Kalenderdatum wechseln.
  static void light() {
    HapticFeedback.selectionClick();
  }

  /// Bestätigung: Folgen, Favorisieren, Erinnerung aktivieren, Liste
  /// anlegen/Event hinzufügen (beim finalen Speichern), Stadt bestätigen,
  /// Interessen-Mindestanzahl erreicht.
  static void confirm() {
    HapticFeedback.mediumImpact();
  }

  /// Deutlich: Registrierung/Anmeldung abgeschlossen, Termin erfolgreich im
  /// Kalender, Check-in, Abzeichen/Meilensteine.
  static void strong() {
    HapticFeedback.heavyImpact();
  }

  /// Weich/zurückhaltend: Entfolgen (statt Folgen), sanftes Ausblenden
  /// ("Nicht interessiert") eines Events.
  static void soft() {
    HapticFeedback.lightImpact();
  }

  /// Warnung: sehr zurückhaltend, nur beim aktiven Öffnen einer
  /// Absage-/Programmänderungs-Meldung durch den Nutzer.
  static void warning() {
    HapticFeedback.mediumImpact();
  }
}
