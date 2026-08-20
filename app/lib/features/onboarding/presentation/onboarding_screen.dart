import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/onboarding/onboarding_status.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/interest_picker.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../profile/presentation/widgets/auth_section.dart';
import '../../profile/presentation/widgets/profile_avatar_editor.dart';

/// Reihenfolge aus dem Onboarding-Konzept: Willkommen (Anmelden/Account
/// erstellen/Gast) -> Account erstellen -> E-Mail bestätigen -> Persönliche
/// Daten -> Interessen -> Standort -> Benachrichtigungen -> Zusammenfassung.
/// "Account erstellen" ist verpflichtend, sobald gewählt — nur der
/// Willkommens-Schritt selbst lässt sich mit "Ohne Account fortfahren"
/// überspringen (die anonyme Bootstrap-Session aus main.dart bleibt aktiv).
enum _Step {
  welcome,
  signUp,
  verifyEmail,
  personalData,
  interests,
  location,
  notifications,
  summary,
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.welcome;
  String? _pendingEmail;

  void _goTo(_Step step) => setState(() => _step = step);

  Future<void> _finish() async {
    await OnboardingStatus.markCompleted();

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && !user.isAnonymous) {
      // Best effort — der lokale Flag oben ist die eigentliche Quelle der
      // Wahrheit fürs erneute Anzeigen; ein Netzwerkfehler hier soll den
      // Nutzer nicht in der Onboarding-Flow festhalten.
      unawaited(
        Supabase.instance.client
            .from('profiles')
            .update({'onboarding_completed': true})
            .eq('id', user.id),
      );
    }

    if (mounted) context.go('/home');
  }

  void _showLoginSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.screenPaddingMobile,
          right: AppSpacing.screenPaddingMobile,
          top: AppSpacing.lg,
          bottom:
              MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: AuthSection(
            onSignedIn: () {
              Navigator.of(sheetContext).pop();
              _finish();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_step) {
          _Step.welcome => _WelcomeStep(
            onCreateAccount: () => _goTo(_Step.signUp),
            onLogIn: _showLoginSheet,
            onContinueAsGuest: _finish,
          ),
          _Step.signUp => _SignUpStep(
            onSignedUp: (email) {
              _pendingEmail = email;
              _goTo(_Step.verifyEmail);
            },
          ),
          _Step.verifyEmail => _VerifyEmailStep(
            email: _pendingEmail ?? '',
            onVerified: () => _goTo(_Step.personalData),
          ),
          _Step.personalData => _PersonalDataStep(
            onSaved: () => _goTo(_Step.interests),
          ),
          _Step.interests => _StepScaffold(
            title: 'Deine Interessen',
            subtitle:
                'Genres, Künstler:innen, Ensembles und Orte — für passendere '
                'Empfehlungen. Kann jederzeit im Profil geändert werden.',
            primaryLabel: 'Weiter',
            onPrimary: () => _goTo(_Step.location),
            child: const InterestPicker(),
          ),
          _Step.location => _LocationStep(
            onFinished: () => _goTo(_Step.notifications),
          ),
          _Step.notifications => _NotificationsStep(
            onFinished: () => _goTo(_Step.summary),
          ),
          _Step.summary => _SummaryStep(onFinished: _finish),
        },
      ),
    );
  }
}

/// Gemeinsames Gerüst für kompakte Schritte (Titel + Inhalt + Primär-Button)
/// — analog zum nativen OnboardingStepScaffold.swift.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
    required this.primaryLabel,
    this.isPrimaryEnabled = true,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.errorMessage,
    this.isWorking = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final String primaryLabel;
  final bool isPrimaryEnabled;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? errorMessage;
  final bool isWorking;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 56, color: colors.accentPrimary),
                const SizedBox(height: AppSpacing.lg),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              child,
              if (errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.error, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: isPrimaryEnabled && !isWorking ? onPrimary : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: colors.accentPrimary,
                ),
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null && onSecondary != null)
                TextButton(
                  onPressed: isWorking ? null : onSecondary,
                  child: Text(secondaryLabel!),
                ),
            ],
          ),
        ),
        if (isWorking)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({
    required this.onCreateAccount,
    required this.onLogIn,
    required this.onContinueAsGuest,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;
  final VoidCallback onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.piano_rounded, size: 72, color: colors.accentPrimary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.onboardingWelcomeTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.onboardingWelcomeSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: onCreateAccount,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: colors.accentPrimary,
            ),
            child: const Text('Account erstellen'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: onLogIn,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('Anmelden'),
          ),
          TextButton(
            onPressed: onContinueAsGuest,
            child: const Text('Ohne Account fortfahren'),
          ),
        ],
      ),
    );
  }
}

class _SignUpStep extends StatefulWidget {
  const _SignUpStep({required this.onSignedUp});

  final void Function(String email) onSignedUp;

  @override
  State<_SignUpStep> createState() => _SignUpStepState();
}

class _SignUpStepState extends State<_SignUpStep> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _acceptedTerms = false;
  bool _isWorking = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  List<(String, bool)> get _requirements {
    final password = _passwordController.text;
    return [
      ('Mindestens 8 Zeichen', password.length >= 8),
      (
        'Groß- und Kleinbuchstaben',
        password.contains(RegExp('[A-Z]')) &&
            password.contains(RegExp('[a-z]')),
      ),
      ('Mindestens eine Zahl', password.contains(RegExp('[0-9]'))),
    ];
  }

  bool get _isValid =>
      _emailController.text.contains('@') &&
      _requirements.every((r) => r.$2) &&
      _passwordController.text == _passwordConfirmController.text &&
      _acceptedTerms;

  Future<void> _signUp() async {
    setState(() {
      _isWorking = true;
      _error = null;
    });
    final email = _emailController.text.trim().toLowerCase();
    try {
      await AuthService.signUp(email: email, password: _passwordController.text);
      widget.onSignedUp(email);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _StepScaffold(
      title: 'Account erstellen',
      subtitle:
          'Mit E-Mail und Passwort — ein Passwort brauchst du nur einmal '
          'festzulegen.',
      isPrimaryEnabled: _isValid,
      onPrimary: _signUp,
      primaryLabel: 'Weiter',
      errorMessage: _error,
      isWorking: _isWorking,
      child: Column(
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              hintText: 'E-Mail-Adresse',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              hintText: 'Passwort',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
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
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final requirement in _requirements)
                Row(
                  children: [
                    Icon(
                      requirement.$2
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 16,
                      color: requirement.$2 ? Colors.green : colors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      requirement.$1,
                      style: TextStyle(
                        fontSize: 12,
                        color: requirement.$2
                            ? Colors.green
                            : colors.textTertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acceptedTerms,
            onChanged: (value) =>
                setState(() => _acceptedTerms = value ?? false),
            title: const Text(
              'Ich akzeptiere die AGB und die Datenschutzerklärung',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyEmailStep extends StatefulWidget {
  const _VerifyEmailStep({required this.email, required this.onVerified});

  final String email;
  final VoidCallback onVerified;

  @override
  State<_VerifyEmailStep> createState() => _VerifyEmailStepState();
}

class _VerifyEmailStepState extends State<_VerifyEmailStep> {
  final _codeController = TextEditingController();
  bool _isWorking = false;
  String? _error;
  bool _didResend = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      await AuthService.verifyEmailCode(
        email: widget.email,
        code: _codeController.text.trim(),
        type: OtpType.signup,
      );
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        unawaited(
          Supabase.instance.client
              .from('profiles')
              .update({
                'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
                'terms_version': 'v1',
              })
              .eq('id', user.id),
        );
      }
      widget.onVerified();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      setState(() => _didResend = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'E-Mail bestätigen',
      subtitle: 'Wir haben einen Code an ${widget.email} geschickt.',
      icon: Icons.mark_email_read_rounded,
      isPrimaryEnabled: _codeController.text.isNotEmpty,
      onPrimary: _verify,
      primaryLabel: 'Bestätigen',
      errorMessage: _error,
      isWorking: _isWorking,
      child: Column(
        children: [
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
            onChanged: (_) => setState(() {}),
          ),
          TextButton(
            onPressed: _isWorking || _didResend ? null : _resend,
            child: Text(
              _didResend ? 'Code erneut verschickt' : 'Code erneut senden',
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalDataStep extends StatefulWidget {
  const _PersonalDataStep({required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<_PersonalDataStep> createState() => _PersonalDataStepState();
}

class _PersonalDataStepState extends State<_PersonalDataStep> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _birthDate;
  bool _isWorking = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      widget.onSaved();
      return;
    }
    setState(() {
      _isWorking = true;
      _error = null;
    });
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
            'first_name': firstName,
            'last_name': lastName,
            'display_name': '$firstName $lastName',
            if (_phoneController.text.trim().isNotEmpty)
              'phone': _phoneController.text.trim(),
            if (_addressController.text.trim().isNotEmpty)
              'address': _addressController.text.trim(),
            if (_birthDate != null)
              'birth_date':
                  '${_birthDate!.year.toString().padLeft(4, '0')}-'
                  '${_birthDate!.month.toString().padLeft(2, '0')}-'
                  '${_birthDate!.day.toString().padLeft(2, '0')}',
          })
          .eq('id', userId);
      widget.onSaved();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return _StepScaffold(
      title: 'Persönliche Daten',
      subtitle: 'Damit dein Profil zu dir passt.',
      isPrimaryEnabled: _isValid,
      onPrimary: _save,
      primaryLabel: 'Weiter',
      errorMessage: _error,
      isWorking: _isWorking,
      child: Column(
        children: [
          if (userId != null) ProfileAvatarEditor(userId: userId),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _firstNameController,
            autofillHints: const [AutofillHints.givenName],
            decoration: const InputDecoration(
              hintText: 'Vorname',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _lastNameController,
            autofillHints: const [AutofillHints.familyName],
            decoration: const InputDecoration(
              hintText: 'Nachname',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _birthDate == null
                  ? 'Geburtstag (optional)'
                  : '${_birthDate!.day}.${_birthDate!.month}.${_birthDate!.year}',
            ),
            trailing: const Icon(Icons.calendar_today_rounded),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _birthDate ?? DateTime(2000),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _birthDate = picked);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(
              hintText: 'Telefonnummer (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _addressController,
            autofillHints: const [AutofillHints.fullStreetAddress],
            decoration: const InputDecoration(
              hintText: 'Adresse / Wohnort (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationStep extends StatefulWidget {
  const _LocationStep({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  bool _requesting = false;
  String? _activeRegionName;

  @override
  void initState() {
    super.initState();
    _loadActiveRegion();
  }

  Future<void> _loadActiveRegion() async {
    try {
      final rows = await Supabase.instance.client
          .from('regions')
          .select('id,name')
          .eq('type', 'city')
          .eq('is_active', true)
          .order('name')
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        setState(() => _activeRegionName = rows.first['name'] as String);
      }
    } catch (_) {
      // Kein aktives Fallback-Label — der manuelle Fallback-Button bleibt
      // trotzdem nutzbar, versucht dann einfach erneut die Region zu laden.
    }
  }

  Future<void> _requestLocation() async {
    setState(() => _requesting = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _useManualFallback();
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        await _useManualFallback();
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      await Supabase.instance.client.rpc(
        'update_home_location',
        params: {'p_lat': position.latitude, 'p_lng': position.longitude},
      );
      widget.onFinished();
    } catch (_) {
      await _useManualFallback();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _useManualFallback() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      widget.onFinished();
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('regions')
          .select('id')
          .eq('type', 'city')
          .eq('is_active', true)
          .order('name')
          .limit(1);
      if (rows.isNotEmpty) {
        await Supabase.instance.client
            .from('profiles')
            .update({'preferred_region_id': rows.first['id']})
            .eq('id', userId);
      }
    } catch (_) {
      // Fallback-Zuordnung ist Best-effort — soll den Nutzer nicht
      // blockieren, wenn sie fehlschlägt.
    }
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Dein Standort',
      subtitle: 'Für Veranstaltungen in deiner Nähe.',
      icon: Icons.location_on_rounded,
      onPrimary: _requesting ? () {} : _requestLocation,
      isPrimaryEnabled: !_requesting,
      primaryLabel: _requesting ? 'Wird ermittelt …' : 'Standort erlauben',
      isWorking: _requesting,
      secondaryLabel: _activeRegionName != null
          ? 'Ohne Standort fortfahren — $_activeRegionName verwenden'
          : 'Ohne Standort fortfahren',
      onSecondary: _requesting ? null : _useManualFallback,
      child: _activeRegionName != null
          ? Text(
              'Klangradar deckt aktuell nur $_activeRegionName ab.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 12.5,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _NotificationsStep extends StatefulWidget {
  const _NotificationsStep({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_NotificationsStep> createState() => _NotificationsStepState();
}

class _NotificationsStepState extends State<_NotificationsStep> {
  bool _requesting = false;

  Future<void> _requestNotifications() async {
    setState(() => _requesting = true);
    await PushService.initialize();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Nichts verpassen',
      subtitle:
          'Aktiviere Hinweise zu neuen Terminen gefolgter Künstler:innen, '
          'Preisänderungen und knappen Tickets.',
      icon: Icons.notifications_active_rounded,
      onPrimary: _requestNotifications,
      primaryLabel: _requesting
          ? 'Wird aktiviert …'
          : 'Benachrichtigungen aktivieren',
      isPrimaryEnabled: !_requesting,
      isWorking: _requesting,
      secondaryLabel: 'Ohne Benachrichtigungen fortfahren',
      onSecondary: _requesting ? null : widget.onFinished,
      child: const SizedBox.shrink(),
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({required this.onFinished});

  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Klangradar ist bereit',
      subtitle: 'Du kannst deine Interessen jederzeit im Profil ergänzen.',
      icon: Icons.check_circle_rounded,
      onPrimary: onFinished,
      primaryLabel: "Los geht's",
      child: const SizedBox.shrink(),
    );
  }
}
