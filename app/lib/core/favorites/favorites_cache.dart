import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lokale Persistenz für Favoriten (Nutzeranfrage Punkt 12, "Offline-
/// Favoriten"/"Konfliktbehandlung"): der zuletzt vom Server bestätigte Stand
/// plus ausstehende, noch nicht synchronisierte Änderungen. Ein Toggle
/// offline schreibt sofort in [pendingChanges] und wirkt lokal sofort —
/// [FavoritesService.toggle] versucht danach den Server-Sync und räumt bei
/// Erfolg aus [pendingChanges] auf.
///
/// Konfliktstrategie: pro Event nur der jeweils LETZTE gewünschte Zustand
/// (`Map<eventId, bool>` statt einer Op-Liste) — mehrfaches Umschalten
/// desselben Events offline kollabiert auf den finalen Wunschzustand statt
/// widersprüchliche Operationen anzuhäufen ("letzter Schreibzugriff
/// gewinnt", die einzig sinnvolle Regel für ein reines Boolean-Favorit ohne
/// serverseitige updated_at-Spalte).
class FavoritesCache {
  const FavoritesCache._();

  static const _knownKey = 'favorites_cache.known_ids';
  static const _pendingKey = 'favorites_cache.pending';

  static Future<Set<String>> knownIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_knownKey) ?? const []).toSet();
  }

  static Future<void> saveKnownIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_knownKey, ids.toList());
  }

  static Future<Map<String, bool>> pendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as bool),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePendingChanges(Map<String, bool> pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, jsonEncode(pending));
  }

  /// Bekannter Serverstand plus ausstehende lokale Änderungen übereinander —
  /// das, was tatsächlich angezeigt werden soll.
  static Future<Set<String>> effectiveIds() async {
    final known = await knownIds();
    final pending = await pendingChanges();
    final effective = {...known};
    for (final entry in pending.entries) {
      if (entry.value) {
        effective.add(entry.key);
      } else {
        effective.remove(entry.key);
      }
    }
    return effective;
  }
}
