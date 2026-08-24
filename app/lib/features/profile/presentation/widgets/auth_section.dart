import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/auth/biometric_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'forgot_password_sheet.dart';

/// Passwort ersetzt den E-Mail-Code als Anmeldeweg (Onboarding-Redesign) —
/// der Code bleibt intern nur für die Signup-Bestätigung. Der Passwort-Reset
/// kehrt über einen sicheren Link in die App zurück.
class AuthSection extends ConsumerStatefulWidget {
  const AuthSection({super.key, this.onSignedIn, this.onCreateAccount});

  /// Wird nach erfolgreicher Anmeldung (Passwort oder OAuth) aufgerufen —
  /// beim Aufruf aus dem Onboarding-"Anmelden"-Sheet nutzt der Aufrufer das,
  /// um das Sheet zu schließen. Im normalen Profil-Tab bleibt es ungesetzt,
  /// dort reicht der automatische Rebuild über currentUserProvider.
  final VoidCallback? onSignedIn;
  final VoidCallback? onCreateAccount;

  @override
  ConsumerState<AuthSection> createState() => _AuthSectionState();
}

class _AuthSectionState extends ConsumerState<AuthSection> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  bool _waitingForOAuth = false;
  String? _error;
  Set<String> _oauthProviders = const {};
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (_waitingForOAuth &&
          state.event == AuthChangeEvent.signedIn &&
          state.session?.user.isAnonymous == false) {
        widget.onSignedIn?.call();
      }
    });
    AuthService.enabledOAuthProviders().then((providers) {
      if (mounted) setState(() => _oauthProviders = providers);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.signInWithPassword(email: email, password: password);
      await _offerBiometrics();
      widget.onSignedIn?.call();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _oauth(
    Future<bool> Function() signIn,
    String providerLabel,
  ) async {
    setState(() {
      _loading = true;
      _waitingForOAuth = true;
      _error = null;
    });
    try {
      final launched = await signIn();
      if (!launched && mounted) {
        setState(() {
          _waitingForOAuth = false;
          _error = '$providerLabel-Anmeldung konnte nicht geöffnet werden.';
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _waitingForOAuth = false;
        _error = '$providerLabel: ${e.message}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _offerBiometrics() async {
    if (!await BiometricAuth.isAvailable ||
        await BiometricAuth.isEnabled ||
        !mounted) {
      return;
    }
    final enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Face ID oder Touch ID aktivieren?'),
        content: const Text(
          'Damit kannst du deinen angemeldeten Account auf diesem Gerät zusätzlich schützen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Später'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aktivieren'),
          ),
        ],
      ),
    );
    if (enable == true) await BiometricAuth.setEnabled(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Image.asset(
            'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.authSignInTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          'Mit E-Mail und Passwort anmelden.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: InputDecoration(
            hintText: l10n.authEmailHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            hintText: 'Passwort',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              tooltip: _showPassword
                  ? 'Passwort verbergen'
                  : 'Passwort anzeigen',
            ),
          ),
          onSubmitted: (_) => _signIn(),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: _loading ? null : _signIn,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            backgroundColor: colors.accentPrimary,
          ),
          child: Text(_loading ? 'Anmeldung läuft …' : 'Anmelden'),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ForgotPasswordSheet(),
                ),
          child: const Text('Passwort vergessen?'),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : (widget.onCreateAccount ?? () => context.push('/onboarding')),
          child: const Text('Noch kein Konto? Registrieren'),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: TextStyle(color: colors.error, fontSize: 12.5)),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: Divider(color: colors.separator)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                l10n.authOr,
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ),
            Expanded(child: Divider(color: colors.separator)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_oauthProviders.contains('apple')) ...[
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () => _oauth(AuthService.signInWithApple, 'Apple'),
            icon: const Icon(Icons.apple, size: 20),
            label: Text(l10n.authSignInWithApple),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_oauthProviders.contains('google'))
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () => _oauth(AuthService.signInWithGoogle, 'Google'),
            icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
            label: Text(l10n.authSignInWithGoogle),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
      ],
    );
  }
}
