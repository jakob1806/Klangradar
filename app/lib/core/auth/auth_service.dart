import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Kapselt Supabase-Auth-Aufrufe. Die reguläre Anmeldung verwendet ein
/// Passwort, die Registrierung einen 6-stelligen Bestätigungscode und die
/// Passwort-Wiederherstellung einen sicheren Deep-Link zurück in die App.
class AuthService {
  const AuthService._();

  static const _oauthRedirect = 'de.klassikmuenchen://login-callback';

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<AuthResponse> verifySignupCode({
    required String email,
    required String code,
  }) {
    return _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.signup,
    );
  }

  /// Onboarding-Redesign: Passwort ersetzt den E-Mail-Code als
  /// Anmeldeweg — der Code bleibt intern nur für die
  /// Signup-Bestätigung. Der Passwort-Reset ist bewusst ein Link-Flow.
  /// Solange
  /// `enable_confirmations` aktiv ist (config.toml), liefert `signUp` noch
  /// keine Session — erst die Bestätigung schaltet den Account frei.
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> requestPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: _oauthRedirect,
    );
  }

  static Future<UserResponse> updatePassword(String password) {
    return _client.auth.updateUser(UserAttributes(password: password));
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
