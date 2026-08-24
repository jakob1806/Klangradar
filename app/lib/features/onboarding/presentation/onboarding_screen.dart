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
  const OnboardingScreen({super.key, this.startWithAccountCreation = false});

  final bool startWithAccountCreation;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late _Step _step;
  String? _pendingEmail;
  bool _pendingMarketingOptIn = false;

  @override
  void initState() {
    super.initState();
    _step = widget.startWithAccountCreation ? _Step.signUp : _Step.welcome;
  }

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
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: AuthSection(
            onSignedIn: () {
              Navigator.of(sheetContext).pop();
              _finish();
            },
            onCreateAccount: () {
              Navigator.of(sheetContext).pop();
              _goTo(_Step.signUp);
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
        child: Column(
          children: [
            if (_progressStep != null)
              _ProgressHeader(current: _progressStep!, total: 6),
            Expanded(
              child: switch (_step) {
                _Step.welcome => _WelcomeStep(
                  onCreateAccount: () => _goTo(_Step.signUp),
                  onLogIn: _showLoginSheet,
                  onContinueAsGuest: _finish,
                  onAuthenticated: _finish,
                ),
                _Step.signUp => _SignUpStep(
                  onSignedUp: (email, marketingOptIn) {
                    _pendingEmail = email;
                    _pendingMarketingOptIn = marketingOptIn;
                    _goTo(_Step.verifyEmail);
                  },
                ),
                _Step.verifyEmail => _VerifyEmailStep(
                  email: _pendingEmail ?? '',
                  marketingEmailOptIn: _pendingMarketingOptIn,
                  onVerified: () => _goTo(_Step.personalData),
                ),
                _Step.personalData => _PersonalDataStep(
                  onSaved: () => _goTo(_Step.interests),
                ),
                _Step.interests => _StepScaffold(
                  title: 'Was interessiert dich?',
                  subtitle:
                      'Genres, Künstler:innen, Ensembles und Orte — für passendere '
                      'Empfehlungen. Kann jederzeit im Profil geändert werden.',
                  primaryLabel: 'Weiter',
                  onPrimary: () => _goTo(_Step.location),
                  secondaryLabel: 'Jetzt überspringen',
                  onSecondary: () => _goTo(_Step.location),
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
          ],
        ),
      ),
    );
  }

  int? get _progressStep => switch (_step) {
    _Step.welcome => null,
    _Step.signUp => 1,
    _Step.verifyEmail => 2,
    _Step.personalData => 3,
    _Step.interests => 4,
    _Step.location => 5,
    _Step.notifications || _Step.summary => 6,
  };
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.sm,
      AppSpacing.xl,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schritt $current von $total',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: current / total),
      ],
    ),
  );
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

class _WelcomeStep extends StatefulWidget {
  const _WelcomeStep({
    required this.onCreateAccount,
    required this.onLogIn,
    required this.onContinueAsGuest,
    required this.onAuthenticated,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;
  final VoidCallback onContinueAsGuest;
  final VoidCallback onAuthenticated;

  @override
  State<_WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<_WelcomeStep> {
  Set<String> _providers = const {};
  bool _loading = false;
  bool _waitingForOAuth = false;
  String? _error;
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
        widget.onAuthenticated();
      }
    });
    AuthService.enabledOAuthProviders().then((value) {
      if (mounted) setState(() => _providers = value);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _oauth(Future<bool> Function() action) async {
    setState(() {
      _loading = true;
      _waitingForOAuth = true;
      _error = null;
    });
    try {
      final launched = await action();
      if (!launched && mounted) {
        setState(() {
          _waitingForOAuth = false;
          _error = 'Anmeldung konnte nicht geöffnet werden.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _waitingForOAuth = false;
          _error = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
          const _KlangradarLogo(size: 88),
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
            onPressed: widget.onLogIn,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: colors.accentPrimary,
            ),
            child: const Text('Anmelden'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: widget.onCreateAccount,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('Konto erstellen'),
          ),
          TextButton(
            onPressed: widget.onContinueAsGuest,
            child: const Text('Ohne Account fortfahren'),
          ),
          if (_providers.contains('apple'))
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _oauth(AuthService.signInWithApple),
              icon: const Icon(Icons.apple),
              label: const Text('Mit Apple anmelden'),
            ),
          if (_providers.contains('google'))
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _oauth(AuthService.signInWithGoogle),
              icon: const Icon(Icons.g_mobiledata_rounded),
              label: const Text('Mit Google anmelden'),
            ),
          if (_error != null)
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
        ],
      ),
    );
  }
}

class _KlangradarLogo extends StatelessWidget {
  const _KlangradarLogo({this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    margin: const EdgeInsets.symmetric(horizontal: 80),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .225),
      boxShadow: const [
        BoxShadow(
          color: Color(0x29000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Image.asset(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      fit: BoxFit.cover,
    ),
  );
}

class _SignUpStep extends StatefulWidget {
  const _SignUpStep({required this.onSignedUp});

  final void Function(String email, bool marketingEmailOptIn) onSignedUp;

  @override
  State<_SignUpStep> createState() => _SignUpStepState();
}

class _SignUpStepState extends State<_SignUpStep> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _marketingEmailOptIn = false;
  bool _showPassword = false;
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
      _acceptedTerms &&
      _acceptedPrivacy;

  Future<void> _signUp() async {
    setState(() {
      _isWorking = true;
      _error = null;
    });
    final email = _emailController.text.trim().toLowerCase();
    try {
      await AuthService.signUp(
        email: email,
        password: _passwordController.text,
      );
      widget.onSignedUp(email, _marketingEmailOptIn);
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
          const _KlangradarLogo(size: 68),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Ein Account synchronisiert Favoriten, Interessen und Erinnerungen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
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
            obscureText: !_showPassword,
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
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              hintText: 'Passwort wiederholen',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showPassword,
            onChanged: (value) => setState(() => _showPassword = value),
            title: const Text('Passwörter anzeigen'),
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
                      color: requirement.$2
                          ? Colors.green
                          : colors.textTertiary,
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
              'Ich akzeptiere die AGB',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acceptedPrivacy,
            onChanged: (value) =>
                setState(() => _acceptedPrivacy = value ?? false),
            title: const Text(
              'Ich habe die Datenschutzerklärung gelesen',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _marketingEmailOptIn,
            onChanged: (value) =>
                setState(() => _marketingEmailOptIn = value ?? false),
            title: const Text(
              'Neuigkeiten per E-Mail (optional)',
              style: TextStyle(fontSize: 12.5),
            ),
            subtitle: const Text(
              'Nicht vorausgewählt und jederzeit widerrufbar.',
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyEmailStep extends StatefulWidget {
  const _VerifyEmailStep({
    required this.email,
    required this.marketingEmailOptIn,
    required this.onVerified,
  });

  final String email;
  final bool marketingEmailOptIn;
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
      await AuthService.verifySignupCode(
        email: widget.email,
        code: _codeController.text.trim(),
      );
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        unawaited(
          Supabase.instance.client
              .from('profiles')
              .update({
                'terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
                'terms_version': 'v1',
                'marketing_email_opt_in': widget.marketingEmailOptIn,
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
  DateTime? _birthDate;
  bool _isWorking = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  bool get _isValid => _firstNameController.text.trim().isNotEmpty;

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
            'display_name': lastName.isEmpty
                ? firstName
                : '$firstName $lastName',
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
    return _StepScaffold(
      title: 'Über dich',
      subtitle:
          'Nur dein Vorname ist erforderlich. Alles Weitere kannst du später ergänzen.',
      isPrimaryEnabled: _isValid,
      onPrimary: _save,
      primaryLabel: 'Weiter',
      errorMessage: _error,
      isWorking: _isWorking,
      child: Column(
        children: [
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
              hintText: 'Nachname (optional)',
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
          Text(
            'Profilbild, Telefonnummer und Adresse sind optional und können später im Profil ergänzt werden.',
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12.5,
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
      title: 'Konzerte in deiner Nähe entdecken',
      subtitle:
          'Dein Standort hilft uns, passende Veranstaltungen in deiner '
          'Umgebung zu zeigen. Du kannst auch nur den ungefähren Standort freigeben.',
      icon: Icons.location_on_rounded,
      onPrimary: _requesting ? () {} : _requestLocation,
      isPrimaryEnabled: !_requesting,
      primaryLabel: _requesting ? 'Wird ermittelt …' : 'Standort erlauben',
      isWorking: _requesting,
      secondaryLabel: _activeRegionName != null
          ? 'Nicht jetzt — $_activeRegionName verwenden'
          : 'Nicht jetzt',
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
  bool _recommendations = true;
  bool _ticketAlerts = true;
  bool _almostSoldOut = true;
  bool _followedArtists = true;
  bool _savedEventReminders = true;

  Future<void> _savePreferences() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await Supabase.instance.client.from('notification_preferences').upsert({
      'user_id': userId,
      'notify_new_matching_events': _recommendations,
      'notify_price_changes': _ticketAlerts,
      'notify_almost_sold_out': _almostSoldOut,
      'followed_ensemble_new_event': _followedArtists,
      'notify_reminder_day_before': _savedEventReminders,
    });
  }

  Future<void> _requestNotifications() async {
    setState(() => _requesting = true);
    try {
      await _savePreferences();
      await PushService.initialize();
      widget.onFinished();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Verpasse keine interessanten Konzerte',
      subtitle:
          'Wähle zuerst aus, was dich interessiert. Den Systemdialog öffnen '
          'wir erst, wenn du anschließend aktivierst.',
      icon: Icons.notifications_active_rounded,
      onPrimary: _requestNotifications,
      primaryLabel: _requesting
          ? 'Wird aktiviert …'
          : 'Benachrichtigungen aktivieren',
      isPrimaryEnabled: !_requesting,
      isWorking: _requesting,
      secondaryLabel: 'Nicht jetzt',
      onSecondary: _requesting
          ? null
          : () {
              unawaited(_savePreferences());
              widget.onFinished();
            },
      child: Column(
        children: [
          SwitchListTile(
            value: _recommendations,
            onChanged: (value) => setState(() => _recommendations = value),
            title: const Text('Konzertempfehlungen'),
          ),
          SwitchListTile(
            value: _ticketAlerts,
            onChanged: (value) => setState(() => _ticketAlerts = value),
            title: const Text('Ticket- und Preis-Alerts'),
          ),
          SwitchListTile(
            value: _almostSoldOut,
            onChanged: (value) => setState(() => _almostSoldOut = value),
            title: const Text('Bald ausverkauft'),
          ),
          SwitchListTile(
            value: _followedArtists,
            onChanged: (value) => setState(() => _followedArtists = value),
            title: const Text('Neue Events favorisierter Künstler:innen'),
          ),
          SwitchListTile(
            value: _savedEventReminders,
            onChanged: (value) => setState(() => _savedEventReminders = value),
            title: const Text('Erinnerungen an gespeicherte Events'),
          ),
        ],
      ),
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({required this.onFinished});

  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Dein Profil ist eingerichtet',
      subtitle: 'Deine persönlichen Konzertempfehlungen sind jetzt bereit.',
      icon: Icons.check_circle_rounded,
      onPrimary: onFinished,
      primaryLabel: 'Konzerte für dich entdecken',
      child: const SizedBox.shrink(),
    );
  }
}
