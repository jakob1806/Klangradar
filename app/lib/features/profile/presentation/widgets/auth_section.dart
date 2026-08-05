import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Auf `true` setzen, sobald ein kostenpflichtiges Apple Developer Program
/// vorhanden und Sign in with Apple im Supabase-Dashboard konfiguriert ist.
const kAppleSignInAvailable = false;

enum _Step { email, code }

class AuthSection extends ConsumerStatefulWidget {
  const AuthSection({super.key});

  @override
  ConsumerState<AuthSection> createState() => _AuthSectionState();
}

class _AuthSectionState extends ConsumerState<AuthSection> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  _Step _step = _Step.email;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.sendEmailCode(email);
      if (!mounted) return;
      setState(() => _step = _Step.code);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.verifyEmailCode(
        email: _emailController.text.trim(),
        code: code,
      );
      // Erfolgreicher Login löst onAuthStateChange aus, ProfileScreen rebuilt automatisch.
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
          l10n.authSignInSubtitle,
          style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_step == _Step.email) ...[
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              hintText: l10n.authEmailHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _loading ? null : _sendCode,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: colors.accentPrimary,
            ),
            child: Text(_loading ? l10n.authSendingCode : l10n.authSendCode),
          ),
        ] else ...[
          Text(
            l10n.authCodeSentTo(_emailController.text.trim()),
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 8),
            decoration: const InputDecoration(
              hintText: '000000',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            maxLength: 6,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _loading ? null : _verifyCode,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: colors.accentPrimary,
            ),
            child: Text(_loading ? l10n.authCheckingCode : l10n.authConfirm),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () => setState(() => _step = _Step.email),
            child: Text(l10n.authUseOtherEmail),
          ),
        ],
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
        // Sign in with Apple braucht ein kostenpflichtiges Apple Developer
        // Program (Services-ID + Key für den Supabase-Dashboard-Provider) —
        // solange das nicht vorhanden ist, würde der Button nur fehlschlagen.
        // Auf `true` setzen, sobald das Programm eingerichtet ist.
        if (kAppleSignInAvailable) ...[
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
