import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Kapselt Supabase-Auth-Aufrufe. E-Mail-Login läuft über einen 6-stelligen
/// Code statt über einen Magic-Link — braucht dadurch keinen registrierten
/// Deep-Link/keine freigegebene Redirect-URL (siehe docs/07-roadmap.md).
/// Sign in with Apple/Google braucht beides und funktioniert erst, sobald
/// die OAuth-Provider im Supabase-Dashboard konfiguriert sind.
class AuthService {
  const AuthService._();

  static const _oauthRedirect = 'de.klassikmuenchen://login-callback';

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> sendEmailCode(String email) {
    return _client.auth.signInWithOtp(email: email, shouldCreateUser: true);
  }

  static Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
  }) {
    return _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
  }

  static Future<bool> signInWithApple() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _oauthRedirect,
    );
  }

  static Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
    );
  }

  static Future<Set<String>> enabledOAuthProviders() async {
    final response = await http.get(
      Uri.parse('${Env.supabaseUrl}/auth/v1/settings'),
      headers: {'apikey': Env.supabaseAnonKey},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return {};
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final external = body['external'] as Map<String, dynamic>? ?? const {};
    return external.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toSet();
  }

  /// Löscht zuerst die eigenen Push-Tokens — sonst würde ein zweiter Nutzer,
  /// der sich danach auf demselben Gerät anmeldet, bis zum nächsten
  /// Push-Berechtigungs-Durchlauf über den fremden, noch verknüpften Token
  /// erreichbar bleiben (token ist unique, der Upsert beim nächsten Login
  /// heilt das zwar selbst, aber erst dann).
  static Future<void> signOut() async {
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      await _client.from('push_tokens').delete().eq('user_id', userId);
    }
    await _client.auth.signOut();
  }
}
