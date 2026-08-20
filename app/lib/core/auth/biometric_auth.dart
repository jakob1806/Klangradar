import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'face_id_protection_enabled';

/// Face ID/Touch ID zum optionalen Schutz des Accounts (Nutzerwunsch) — kein
/// Ersatz für den Netzwerk-Login, sondern eine zusätzliche Sperre, die der
/// Nutzer in den Profil-Einstellungen aktivieren kann.
class BiometricAuth {
  const BiometricAuth._();

  static final _auth = LocalAuthentication();

  static Future<bool> get isAvailable async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }
}
