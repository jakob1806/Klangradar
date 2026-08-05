import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'app_locale';

/// Sprachwahl (Phase D.4, docs/09-feature-expansion-plan.md) — nach
/// demselben Muster wie theme_mode_provider.dart: startet mit einem
/// sicheren Default, lädt die gespeicherte Wahl asynchron nach. Anders als
/// beim Theme (Default: Systemeinstellung) ist der Default hier explizit
/// Deutsch (`null`), nicht die Systemsprache — die App war bisher komplett
/// Deutsch-only, ein automatischer Sprung auf Englisch für Nutzer:innen
/// mit englischem Systemgerät wäre eine unangekündigte Verhaltensänderung.
/// `null` bedeutet "Systemsprache folgen", explizit gesetzt override das.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    _load();
    return const Locale('de');
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) {
      return; // noch nie geändert -> beim Deutsch-Default bleiben
    }
    state = saved == 'system' ? null : Locale(saved);
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale?.languageCode ?? 'system');
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);
