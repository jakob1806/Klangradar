import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Nutzerwunsch: "auch wäre es noch praktisch, wenn ich in der app auch das
/// admin portal auf machen kann. z.b. über die einstellungen mit einem
/// bestimmten passwort." Die Passwortprüfung UND die Ziel-URL kommen aus
/// der verify-admin-access Edge Function, nicht aus App-Konstanten — so
/// bleibt beides änderbar (z.B. bei Domain-Wechsel), ohne ein App-Update zu
/// brauchen, und das echte Passwort steht nie im App-Bundle.
Future<void> showAdminPortalDialog(BuildContext context) async {
  final controller = TextEditingController();
  final l10n = AppLocalizations.of(context)!;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _AdminPasswordDialog(
      controller: controller,
      l10n: l10n,
    ),
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
  bool _checking = false;
  String? _error;

  Future<void> _submit() async {
    final password = widget.controller.text;
    if (password.isEmpty) return;

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'verify-admin-access',
        body: {'password': password},
      );
      final data = response.data as Map<String, dynamic>?;
      final valid = data?['valid'] == true;
      final portalUrl = data?['portalUrl'] as String?;

      if (!mounted) return;

      if (!valid || portalUrl == null || portalUrl.isEmpty) {
        setState(() {
          _checking = false;
          _error = widget.l10n.adminPortalWrongPassword;
        });
        return;
      }

      Navigator.of(context).pop();
      await launchUrl(
        Uri.parse(portalUrl),
        mode: LaunchMode.externalApplication,
      );
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
      content: TextField(
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
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: Text(widget.l10n.adminPortalCancel),
        ),
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
