import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/home/application/home_providers.dart';

/// Stale-while-revalidate-Cache für den Home-Feed (Perf-Audit Punkt 1):
/// homeDataProvider zeigt beim Start sofort den zuletzt geladenen Stand aus
/// SharedPreferences, während im Hintergrund neu geladen wird — statt bei
/// jedem Öffnen erst eine 11-Request-Antwort abzuwarten bzw. bei fehlendem
/// Netz komplett leer zu bleiben.
class HomeCache {
  const HomeCache._();

  static const _key = 'home_cache_v1';

  /// Nach dieser Zeit gilt ein Cache-Treffer als zu alt, um überhaupt noch
  /// angezeigt zu werden (z. B. nach tagelanger Abwesenheit) — verhindert,
  /// dass offline sichtbar veraltete Ankündigungen/Preise hängen bleiben.
  static const maxAge = Duration(hours: 12);

  /// Bindet den Cache an Stadt + Nutzer — sonst würde ein Stadtwechsel oder
  /// Login/Logout kurzzeitig den Feed der falschen Stadt/des falschen
  /// Nutzers zeigen, bevor die Neuladung durch ist.
  static Future<HomeData?> load({
    required String cityKey,
    required String userKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['cityKey'] != cityKey || envelope['userKey'] != userKey) {
        return null;
      }
      final savedAt = DateTime.tryParse(envelope['savedAt'] as String? ?? '');
      if (savedAt == null ||
          DateTime.now().difference(savedAt) > maxAge) {
        return null;
      }
      return HomeData.fromJson(envelope['data'] as Map<String, dynamic>);
    } catch (_) {
      // Beschädigter/inkompatibler Cache-Eintrag (z. B. nach einem
      // App-Update mit geändertem Format) — einfach ignorieren, der Feed
      // lädt dann ganz normal frisch.
      return null;
    }
  }

  static Future<void> save(
    HomeData data, {
    required String cityKey,
    required String userKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final envelope = {
        'cityKey': cityKey,
        'userKey': userKey,
        'savedAt': DateTime.now().toIso8601String(),
        'data': data.toJson(),
      };
      await prefs.setString(_key, jsonEncode(envelope));
    } catch (_) {
      // Cache-Schreibfehler dürfen den Feed nicht zum Absturz bringen.
    }
  }
}
