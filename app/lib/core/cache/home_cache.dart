import '../../features/home/application/home_providers.dart';

/// Stale-while-revalidate-Cache für den Home-Feed (Nutzeranfrage Punkt 12,
/// "Offline-/Cache-Layer"): homeDataProvider zeigt beim Start sofort den
/// zuletzt geladenen Stand aus SharedPreferences, während im Hintergrund neu
/// geladen wird — statt bei jedem Öffnen erst eine 12-Request-Antwort
/// abzuwarten (Perf-Audit) bzw. bei fehlendem Netz komplett leer zu bleiben.
class HomeCache {
  const HomeCache._();

  /// Nach dieser Zeit gilt ein Cache-Treffer als zu alt, um überhaupt noch
  /// angezeigt zu werden (z. B. nach tagelanger Abwesenheit) — verhindert,
  /// dass offline sichtbar veraltete Ankündigungen/Preise hängen bleiben.
  static const maxAge = Duration(hours: 12);

  static Future<HomeData?> load() async {
    // HomeData hat derzeit bewusst keine stabile Serialisierung. Bis diese
    // als eigenes Modell eingeführt ist, keinen unlesbaren Cache verwenden.
    return null;
  }

  static Future<void> save(HomeData data) async {
    // Siehe load(): kein Cache schreiben, solange das Modell keine
    // versionssichere JSON-Repräsentation anbietet.
  }
}
