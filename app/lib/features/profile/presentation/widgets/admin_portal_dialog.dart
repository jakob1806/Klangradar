import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Prüft beim Öffnen zuerst die echte Supabase-Sitzung. Server-seitig
/// freigegebene Konten öffnen das Portal direkt; nur alle anderen sehen die
/// Passwortabfrage. Weder Allowlist noch Passwort stehen im App-Bundle.
Future<void> showAdminPortalDialog(BuildContext context) async {
  final controller = TextEditingController();
  final l10n = AppLocalizations.of(context)!;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _AdminPasswordDialog(controller: controller, l10n: l10n),
  );
}

class _AdminPasswordDialog extends StatefulWidget {
  const _AdminPasswordDialog({required this.controller, required this.l10n});

  final TextEditingController controller;
  final AppLocalizations l10n;

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  bool _checking = true;
  bool _checkingAccount = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAccountAccess();
  }

  Future<Map<String, dynamic>?> _verifyAccess({String? password}) async {
    final response = await Supabase.instance.client.functions.invoke(
      'verify-admin-access',
      body: password == null ? <String, dynamic>{} : {'password': password},
    );
    return response.data as Map<String, dynamic>?;
  }

  Future<void> _checkAccountAccess() async {
    try {
      final data = await _verifyAccess();
      if (!mounted) return;

      if (data?['valid'] == true &&
          await _openPortal(data?['portalUrl'] as String?)) {
        return;
      }

      setState(() {
        _checking = false;
        _checkingAccount = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkingAccount = false;
        _error = widget.l10n.adminPortalError;
      });
    }
  }

  Future<bool> _openPortal(String? portalUrl) async {
    if (portalUrl == null || portalUrl.isEmpty) return false;
    final launched = await launchUrl(
      Uri.parse(portalUrl),
      mode: LaunchMode.externalApplication,
    );
    if (launched && mounted) Navigator.of(context).pop();
    return launched;
  }

  Future<void> _submit() async {
    final password = widget.controller.text;
    if (password.isEmpty) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final data = await _verifyAccess(password: password);
      final valid = data?['valid'] == true;
      final portalUrl = data?['portalUrl'] as String?;

      if (!mounted) return;

      if (!valid || !await _openPortal(portalUrl)) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _error = widget.l10n.adminPortalWrongPassword;
        });
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = widget.l10n.adminPortalError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      title: Text(widget.l10n.adminPortalTitle),
      content: _checkingAccount
          ? const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            )
          : TextField(
              controller: widget.controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.l10n.adminPortalPasswordHint,
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
      actions: [
        TextButton(
          onPressed: _checking && !_checkingAccount
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(widget.l10n.adminPortalCancel),
        ),
        if (!_checkingAccount)
          TextButton(
            onPressed: _checking ? null : _submit,
            child: _checking
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accentPrimary,
                    ),
                  )
                : Text(widget.l10n.adminPortalOpen),
          ),
      ],
    );
  }
}
