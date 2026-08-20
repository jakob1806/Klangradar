import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/home/application/home_providers.dart';

/// Stale-while-revalidate-Cache für den Home-Feed (Nutzeranfrage Punkt 12,
/// "Offline-/Cache-Layer"): homeDataProvider zeigt beim Start sofort den
/// zuletzt geladenen Stand aus SharedPreferences, während im Hintergrund neu
/// geladen wird — statt bei jedem Öffnen erst eine 12-Request-Antwort
/// abzuwarten (Perf-Audit) bzw. bei fehlendem Netz komplett leer zu bleiben.
class HomeCache {
  const HomeCache._();

  static const _dataKey = 'home_cache.data';
  static const _savedAtKey = 'home_cache.saved_at';

  /// Nach dieser Zeit gilt ein Cache-Treffer als zu alt, um überhaupt noch
  /// angezeigt zu werden (z. B. nach tagelanger Abwesenheit) — verhindert,
  /// dass offline sichtbar veraltete Ankündigungen/Preise hängen bleiben.
  static const maxAge = Duration(hours: 12);

  static Future<HomeData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dataKey);
    final savedAtMillis = prefs.getInt(_savedAtKey);
    if (raw == null || savedAtMillis == null) return null;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMillis);
    if (DateTime.now().difference(savedAt) > maxAge) return null;
    try {
      return HomeData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Format hat sich zwischen App-Versionen geändert o.ä. — Cache
      // verwerfen statt mit einem Parse-Fehler die ganze Startseite zu
      // blockieren, save() überschreibt ihn beim nächsten Erfolg ohnehin.
      return null;
    }
  }

  static Future<void> save(HomeData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataKey, jsonEncode(data.toJson()));
    await prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
  }
}
