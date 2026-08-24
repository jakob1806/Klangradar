import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Recovery ist bewusst ein Link-Flow. Der Link öffnet die App und Supabase
/// meldet `passwordRecovery`; main.dart navigiert dann zu /reset-password.
class ForgotPasswordSheet extends StatefulWidget {
  const ForgotPasswordSheet({super.key});

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.requestPasswordReset(_email.text.trim().toLowerCase());
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPaddingMobile,
          AppSpacing.lg,
          AppSpacing.screenPaddingMobile,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Passwort zurücksetzen',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _sent
                  ? 'Öffne den sicheren Link aus der E-Mail auf diesem Gerät. Prüfe auch deinen Spam-Ordner.'
                  : 'Wir schicken dir einen sicheren Link, mit dem du ein neues Passwort festlegen kannst.',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!_sent)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'E-Mail-Adresse'),
              )
            else
              Icon(
                Icons.mark_email_read_rounded,
                size: 56,
                color: colors.accentPrimary,
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _loading
                  ? null
                  : (_sent ? () => Navigator.pop(context) : _send),
              child: Text(
                _loading
                    ? 'Bitte warten …'
                    : (_sent ? 'Fertig' : 'Reset-Link senden'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  bool get _valid {
    final value = _password.text;
    return value.length >= 8 &&
        RegExp('[A-Z]').hasMatch(value) &&
        RegExp('[a-z]').hasMatch(value) &&
        RegExp('[0-9]').hasMatch(value) &&
        value == _confirmation.text;
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.updatePassword(_password.text);
      if (mounted) context.go('/home');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Neues Passwort')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(labelText: 'Neues Passwort'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _confirmation,
          obscureText: !_showPassword,
          decoration: const InputDecoration(labelText: 'Passwort bestätigen'),
          onChanged: (_) => setState(() {}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _showPassword,
          onChanged: (value) => setState(() => _showPassword = value),
          title: const Text('Passwörter anzeigen'),
        ),
        for (final item in <(String, bool)>[
          ('Mindestens 8 Zeichen', _password.text.length >= 8),
          (
            'Groß- und Kleinbuchstaben',
            RegExp('[A-Z]').hasMatch(_password.text) &&
                RegExp('[a-z]').hasMatch(_password.text),
          ),
          ('Mindestens eine Zahl', RegExp('[0-9]').hasMatch(_password.text)),
        ])
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(item.$2 ? Icons.check_circle : Icons.circle_outlined),
            title: Text(item.$1),
          ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: context.appColors.error)),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _valid && !_loading ? _save : null,
          child: const Text('Passwort speichern'),
        ),
      ],
    ),
  );
}
