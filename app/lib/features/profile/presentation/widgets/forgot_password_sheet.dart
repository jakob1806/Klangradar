import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

enum _Step { email, code, password, done }

/// "Passwort vergessen"-Flow: E-Mail -> Code aus der Recovery-Mail -> neues
/// Passwort. Nutzt denselben `verify`-Endpoint wie die Signup-Bestätigung,
/// nur mit `OtpType.recovery` (siehe AuthService.verifyEmailCode).
class ForgotPasswordSheet extends StatefulWidget {
  const ForgotPasswordSheet({super.key});

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  _Step _step = _Step.email;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (_step) {
        case _Step.email:
          await AuthService.requestPasswordReset(_emailController.text.trim());
          setState(() => _step = _Step.code);
        case _Step.code:
          await AuthService.verifyEmailCode(
            email: _emailController.text.trim(),
            code: _codeController.text.trim(),
            type: OtpType.recovery,
          );
          setState(() => _step = _Step.password);
        case _Step.password:
          if (_passwordController.text.length < 8) {
            setState(() => _error = 'Mindestens 8 Zeichen.');
            return;
          }
          if (_passwordController.text != _passwordConfirmController.text) {
            setState(() => _error = 'Die Passwörter stimmen nicht überein.');
            return;
          }
          await AuthService.updatePassword(_passwordController.text);
          setState(() => _step = _Step.done);
        case _Step.done:
          if (mounted) Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenPaddingMobile,
        right: AppSpacing.screenPaddingMobile,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Passwort vergessen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_step == _Step.email) ...[
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'E-Mail-Adresse',
                border: OutlineInputBorder(),
              ),
            ),
          ] else if (_step == _Step.code) ...[
            Text(
              'Wir haben einen Code an ${_emailController.text.trim()} geschickt.',
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
          ] else if (_step == _Step.password) ...[
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                hintText: 'Neues Passwort (mind. 8 Zeichen)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _passwordConfirmController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                hintText: 'Passwort wiederholen',
                border: OutlineInputBorder(),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Icon(Icons.check_circle, color: colors.accentPrimary),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(child: Text('Dein Passwort wurde geändert.')),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: TextStyle(color: colors.error, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: colors.accentPrimary,
            ),
            child: Text(_primaryLabel),
          ),
        ],
      ),
    );
  }

  String get _primaryLabel {
    if (_loading) return 'Bitte warten …';
    switch (_step) {
      case _Step.email:
        return 'Code senden';
      case _Step.code:
        return 'Code bestätigen';
      case _Step.password:
        return 'Passwort speichern';
      case _Step.done:
        return 'Fertig';
    }
  }
}
