import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'forgot_password_sheet.dart';

/// Passwort ersetzt den E-Mail-Code als Anmeldeweg (Onboarding-Redesign) —
/// der Code bleibt intern nur für Signup-Bestätigung und Passwort-Reset
/// (siehe forgot_password_sheet.dart und den Onboarding-Signup-Schritt).
class AuthSection extends ConsumerStatefulWidget {
  const AuthSection({super.key, this.onSignedIn});

  /// Wird nach erfolgreicher Anmeldung (Passwort oder OAuth) aufgerufen —
  /// beim Aufruf aus dem Onboarding-"Anmelden"-Sheet nutzt der Aufrufer das,
  /// um das Sheet zu schließen. Im normalen Profil-Tab bleibt es ungesetzt,
  /// dort reicht der automatische Rebuild über currentUserProvider.
  final VoidCallback? onSignedIn;

  @override
  ConsumerState<AuthSection> createState() => _AuthSectionState();
}

class _AuthSectionState extends ConsumerState<AuthSection> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  Set<String> _oauthProviders = const {};

  @override
  void initState() {
    super.initState();
    AuthService.enabledOAuthProviders().then((providers) {
      if (mounted) setState(() => _oauthProviders = providers);
    });
  }

  @override
  void dispose() {
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
      // Erfolgreicher Login löst onAuthStateChange aus, ProfileScreen rebuilt automatisch.
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
      _error = null;
    });
    try {
      await signIn();
      widget.onSignedIn?.call();
    } on AuthException catch (e) {
      setState(() => _error = '$providerLabel: ${e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        CircleAvatar(radius: 32, backgroundColor: colors.accentPrimary),
        const SizedBox(height: AppSpacing.sm),
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
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(
            hintText: 'Passwort',
            border: OutlineInputBorder(),
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
