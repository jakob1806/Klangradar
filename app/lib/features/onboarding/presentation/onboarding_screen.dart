import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/interests/interests_providers.dart';
import '../../../core/notifications/notification_preferences_providers.dart';
import '../../../core/onboarding/onboarding_status.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/interest_picker.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../follows/application/follows_providers.dart';
import '../../profile/presentation/widgets/auth_section.dart';

/// Reihenfolge aus dem Onboarding-Konzept: Willkommen (Anmelden/Account
/// erstellen/Gast) -> Account erstellen -> E-Mail bestätigen -> Persönliche
/// Daten -> Interessen -> Standort -> Personen/Ensembles/Venues folgen ->
/// Benachrichtigungen -> Zusammenfassung. "Account erstellen" ist
/// verpflichtend, sobald gewählt — nur der Willkommens-Schritt selbst lässt
/// sich mit "Ohne Account fortfahren" überspringen (die anonyme
/// Bootstrap-Session aus main.dart bleibt aktiv).
enum _Step {
  welcome,
  signUp,
  verifyEmail,
  personalData,
  interests,
  location,
  follow,
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
              _ProgressHeader(current: _progressStep!, total: 7),
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
                  onFinished: () => _goTo(_Step.follow),
                ),
                _Step.follow => _FollowStep(
                  onFinished: () => _goTo(_Step.notifications),
                ),
                _Step.notifications => _NotificationsStep(
                  onFinished: () => _goTo(_Step.summary),
                ),
                _Step.summary => _SummaryStep(
                  onFinished: _finish,
                  onEditLocation: () => _goTo(_Step.location),
                  onEditInterests: () => _goTo(_Step.interests),
                  onEditFollows: () => _goTo(_Step.follow),
                  onEditNotifications: () => _goTo(_Step.notifications),
                ),
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
    _Step.follow => 6,
    _Step.notifications || _Step.summary => 7,
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
            title: GestureDetector(
              onTap: () => context.push('/legal/terms'),
              child: const Text(
                'Ich akzeptiere die AGB',
                style: TextStyle(
                  fontSize: 12.5,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acceptedPrivacy,
            onChanged: (value) =>
                setState(() => _acceptedPrivacy = value ?? false),
            title: GestureDetector(
              onTap: () => context.push('/legal/privacy'),
              child: const Text(
                'Ich habe die Datenschutzerklärung gelesen',
                style: TextStyle(
                  fontSize: 12.5,
                  decoration: TextDecoration.underline,
                ),
              ),
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
          Text(
            'Optional — hilft uns bei Altersfreigaben und passenderen '
            'Empfehlungen (z.B. Familienkonzerte).',
            style: TextStyle(
              color: context.appColors.textTertiary,
              fontSize: 11.5,
            ),
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

/// Eine Stadt aus der `city_regions`-View (siehe
/// backend/supabase/migrations/20261031000001_city_model_regions_extension.sql).
/// Alle fünf Städte werden im Onboarding fest angezeigt — unabhängig von
/// `isActive` —, nur `editorialStatus != 'live'` bekommt ein
/// "bald verfügbar"-Badge (Nutzervorgabe).
class _CityRegion {
  const _CityRegion({
    required this.id,
    required this.slug,
    required this.nameDe,
    required this.regionName,
    required this.editorialStatus,
    required this.sortOrder,
  });

  factory _CityRegion.fromRow(Map<String, dynamic> row) => _CityRegion(
    id: row['id'] as String,
    slug: row['slug'] as String,
    nameDe: row['name_de'] as String,
    regionName: row['region_name'] as String?,
    editorialStatus: row['editorial_status'] as String? ?? 'live',
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String slug;
  final String nameDe;
  final String? regionName;
  final String editorialStatus;
  final int sortOrder;

  bool get isLive => editorialStatus == 'live';
}

/// Generated by Claude Code
/// Schritt 4 aus dem Onboarding-Konzept — echter Auswahl-Screen mit allen
/// fünf Städten aus `city_regions` statt eines reinen Ja/Nein-Fallbacks.
/// GPS bleibt als zusätzliche Abkürzung bestehen und schreibt weiterhin über
/// die bestehende `update_home_location`-RPC; die manuelle Auswahl schreibt
/// direkt `profiles.preferred_region_id` (unverändertes Feld/Mechanismus).
class _LocationStep extends StatefulWidget {
  const _LocationStep({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  bool _requestingGps = false;
  bool _saving = false;
  bool _loadingCities = true;
  List<_CityRegion> _cities = const [];
  String? _selectedCityId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    try {
      final rows = await Supabase.instance.client
          .from('city_regions')
          .select('id,slug,name_de,region_name,editorial_status,sort_order')
          .order('sort_order');
      final cities = rows.map(_CityRegion.fromRow).toList();
      if (mounted) {
        setState(() {
          _cities = cities;
          // München (live) ist voreingestellt — Nutzer:in kann jede der
          // fünf Städte wählen, "Weiter" funktioniert daher sofort.
          _selectedCityId = cities
              .firstWhere(
                (c) => c.isLive,
                orElse: () => cities.first,
              )
              .id;
          _loadingCities = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCities = false;
          _error = 'Städte konnten nicht geladen werden.';
        });
      }
    }
  }

  Future<void> _saveSelectedCity() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _selectedCityId == null) {
      widget.onFinished();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'preferred_region_id': _selectedCityId})
          .eq('id', userId);
      widget.onFinished();
    } catch (e) {
      setState(() => _error = 'Auswahl konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestGpsLocation() async {
    setState(() {
      _requestingGps = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Kein GPS-Zugriff — Nutzer:in bleibt bei der manuellen Auswahl
        // unten, die Liste ist bereits sichtbar.
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      await Supabase.instance.client.rpc(
        'update_home_location',
        params: {'p_lat': position.latitude, 'p_lng': position.longitude},
      );
      widget.onFinished();
    } catch (_) {
      // Best effort — bei Fehlern bleibt die manuelle Städteliste als
      // gleichwertiger Weg bestehen.
    } finally {
      if (mounted) setState(() => _requestingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _StepScaffold(
      title: 'Wo möchtest du Konzerte entdecken?',
      subtitle:
          'Wähle deine Stadt für passende Empfehlungen in deiner Nähe — '
          'du kannst das jederzeit im Profil ändern.',
      icon: Icons.location_on_rounded,
      isPrimaryEnabled: !_saving && !_requestingGps && _selectedCityId != null,
      onPrimary: _saveSelectedCity,
      primaryLabel: _saving ? 'Wird gespeichert …' : 'Weiter',
      errorMessage: _error,
      isWorking: _saving,
      child: _loadingCities
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _requestingGps ? null : _requestGpsLocation,
                  icon: _requestingGps
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(
                    _requestingGps
                        ? 'Standort wird ermittelt …'
                        : 'Standort automatisch erkennen',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: Divider(color: colors.separator)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        'oder wähle deine Stadt',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: colors.separator)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final city in _cities)
                  _CityOptionCard(
                    city: city,
                    selected: city.id == _selectedCityId,
                    onTap: () => setState(() => _selectedCityId = city.id),
                  ),
              ],
            ),
    );
  }
}

/// Radio-artige Auswahlkarte für eine Stadt (Schritt 4). Städte mit
/// `editorial_status != 'live'` bekommen ein "bald verfügbar"-Badge, bleiben
/// aber auswählbar.
class _CityOptionCard extends StatelessWidget {
  const _CityOptionCard({
    required this.city,
    required this.selected,
    required this.onTap,
  });

  final _CityRegion city;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected
            ? colors.accentPrimary.withValues(alpha: 0.08)
            : colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected ? colors.accentPrimary : colors.separator,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.accentPrimary : colors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        city.nameDe,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (city.regionName != null)
                        Text(
                          city.regionName!,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!city.isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(
                        AppRadius.glassCapsule,
                      ),
                    ),
                    child: Text(
                      'bald verfügbar',
                      style: TextStyle(
                        color: colors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ein Festival/Veranstalter-Eintrag für den "Folgen"-Tab. Eigene, kleine
/// Datenklasse statt Erweiterung von [InterestOption]/[InterestCategory]:
/// Festivals werden bereits an anderer Stelle (festival_follow_button.dart)
/// bewusst isoliert von diesem Enum gehalten, weil es an vielen Stellen
/// exhaustiv geswitcht wird — dieselbe Begründung gilt hier.
class _FestivalOption {
  const _FestivalOption({required this.id, required this.name});

  final String id;
  final String name;
}

final _festivalOptionsProvider =
    FutureProvider.autoDispose<List<_FestivalOption>>((ref) async {
      final rows = await Supabase.instance.client
          .from('festivals')
          .select('id, name')
          .order('name');
      return (rows as List)
          .map(
            (r) => _FestivalOption(
              id: r['id'] as String,
              name: r['name'] as String,
            ),
          )
          .toList();
    });

final _followedFestivalIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const {};
  final rows = await Supabase.instance.client
      .from('user_favorite_festivals')
      .select('festival_id')
      .eq('user_id', user.id);
  return (rows as List).map((r) => r['festival_id'] as String).toSet();
});

/// Generated by Claude Code
/// Schritt 6 aus dem Onboarding-Konzept — "Personen/Ensembles/Venues folgen
/// (getrennte Bereiche, Suche, Vorschläge, 'Alle überspringen', kein
/// Zwang)". Nutzt bewusst die schon vorhandenen Tabellen/Provider statt
/// neuer Datenquellen: user_favorite_persons/_ensembles/_venues über
/// [InterestsService]/[InterestCategory] (dieselbe Persistenz wie der
/// Interessen-Picker in Schritt 5 — "Personen" zeigt hier dieselben
/// Komponist:innen wie dort, ein Folgen in Schritt 5 taucht hier also
/// bereits als ausgewählt auf) und user_favorite_festivals für den vierten
/// Tab. Kein neues Backend-Schema angelegt.
class _FollowStep extends StatefulWidget {
  const _FollowStep({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_FollowStep> createState() => _FollowStepState();
}

class _FollowStepState extends State<_FollowStep> {
  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Wem möchtest du folgen?',
      subtitle:
          'Personen, Ensembles, Venues und Festivals — du bekommst dann '
          'Neuigkeiten zu ihnen. Ganz ohne Auswahl geht es auch.',
      primaryLabel: 'Weiter',
      onPrimary: widget.onFinished,
      secondaryLabel: 'Alle überspringen',
      onSecondary: widget.onFinished,
      child: SizedBox(
        // Feste Höhe nötig, weil _StepScaffold in eine
        // SingleChildScrollView eingebettet ist und TabBarView selbst
        // unbeschränkte Höhe verlangt.
        height: 420,
        child: DefaultTabController(
          length: 4,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: context.appColors.accentPrimary,
                unselectedLabelColor: context.appColors.textSecondary,
                indicatorColor: context.appColors.accentPrimary,
                tabs: const [
                  Tab(text: 'Personen'),
                  Tab(text: 'Ensembles'),
                  Tab(text: 'Venues'),
                  Tab(text: 'Festivals'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Expanded(
                child: TabBarView(
                  children: [
                    _FollowCategoryTab(category: InterestCategory.person),
                    _FollowCategoryTab(category: InterestCategory.ensemble),
                    _FollowCategoryTab(category: InterestCategory.venue),
                    _FollowFestivalsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Tab für Personen/Ensembles/Venues — nutzt dieselben Optionen-Provider
/// wie [InterestPicker] (composerOptionsProvider/ensembleOptionsProvider/
/// venueOptionsProvider) und [InterestsService.toggle] zum Folgen/Entfolgen.
class _FollowCategoryTab extends ConsumerStatefulWidget {
  const _FollowCategoryTab({required this.category});

  final InterestCategory category;

  @override
  ConsumerState<_FollowCategoryTab> createState() =>
      _FollowCategoryTabState();
}

class _FollowCategoryTabState extends ConsumerState<_FollowCategoryTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final options = switch (widget.category) {
      InterestCategory.person =>
        ref.watch(composerOptionsProvider).valueOrNull ?? const [],
      InterestCategory.ensemble =>
        ref.watch(ensembleOptionsProvider).valueOrNull ?? const [],
      InterestCategory.venue =>
        ref.watch(venueOptionsProvider).valueOrNull ?? const [],
      InterestCategory.genre => const <InterestOption>[],
    };
    final selected = ref.watch(userInterestsProvider).valueOrNull;
    final selectedIds = switch (widget.category) {
      InterestCategory.person => selected?.personIds ?? const {},
      InterestCategory.ensemble => selected?.ensembleIds ?? const {},
      InterestCategory.venue => selected?.venueIds ?? const {},
      InterestCategory.genre => const <String>{},
    };

    if (options.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Vorschläge: bis zu drei noch nicht gefolgte Einträge — eine echte
    // Personalisierung nach den in Schritt 5 gewählten Genres würde eine
    // Genre<->Person/Ensemble/Venue-Zuordnungstabelle voraussetzen, die es
    // im Schema (noch) nicht gibt (siehe PR-Beschreibung, offener Punkt).
    // Schon in Schritt 5 gefolgte Einträge (z.B. Komponist:innen als
    // Interesse) erscheinen hier automatisch als "bereits gefolgt", weil
    // dieselbe Tabelle genutzt wird.
    final suggestions = options
        .where((o) => !selectedIds.contains(o.id))
        .take(3)
        .toList();

    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? options
        : options
              .where((o) => o.label.toLowerCase().contains(normalizedQuery))
              .toList();
    final selectedFirst = [
      ...filtered.where((o) => selectedIds.contains(o.id)),
      ...filtered.where((o) => !selectedIds.contains(o.id)),
    ];

    return ListView(
      children: [
        if (suggestions.isNotEmpty) ...[
          Text(
            'Vorschläge',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in suggestions)
                ActionChip(
                  avatar: Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: colors.accentPrimary,
                  ),
                  label: Text(option.label),
                  onPressed: () => InterestsService.toggle(
                    ref,
                    category: widget.category,
                    id: option.id,
                    isSelected: false,
                  ),
                  backgroundColor: colors.accentPrimary.withValues(
                    alpha: 0.08,
                  ),
                  side: BorderSide(color: colors.accentPrimary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Suchen …',
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: colors.textTertiary,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            filled: true,
            fillColor: colors.backgroundPrimary,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              borderSide: BorderSide(color: colors.separator),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              borderSide: BorderSide(color: colors.separator),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in selectedFirst)
              FilterChip(
                label: Text(option.label),
                selected: selectedIds.contains(option.id),
                onSelected: (_) => InterestsService.toggle(
                  ref,
                  category: widget.category,
                  id: option.id,
                  isSelected: selectedIds.contains(option.id),
                ),
                selectedColor: colors.accentPrimary.withValues(alpha: 0.16),
                backgroundColor: colors.backgroundSecondary,
                side: BorderSide(
                  color: selectedIds.contains(option.id)
                      ? colors.accentPrimary
                      : colors.separator,
                ),
                labelStyle: TextStyle(
                  color: selectedIds.contains(option.id)
                      ? colors.accentPrimary
                      : colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Vierter Tab: Festivals/Veranstalter — nutzt user_favorite_festivals
/// direkt (analog zu FestivalFollowButton), da Festivals bewusst nicht Teil
/// von [InterestCategory] sind.
class _FollowFestivalsTab extends ConsumerStatefulWidget {
  const _FollowFestivalsTab();

  @override
  ConsumerState<_FollowFestivalsTab> createState() =>
      _FollowFestivalsTabState();
}

class _FollowFestivalsTabState extends ConsumerState<_FollowFestivalsTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggle(String festivalId, bool isFollowing) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (isFollowing) {
      await Supabase.instance.client
          .from('user_favorite_festivals')
          .delete()
          .eq('user_id', user.id)
          .eq('festival_id', festivalId);
    } else {
      await Supabase.instance.client
          .from('user_favorite_festivals')
          .upsert(
            {'user_id': user.id, 'festival_id': festivalId},
            onConflict: 'user_id,festival_id',
            ignoreDuplicates: true,
          );
    }
    ref.invalidate(_followedFestivalIdsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final festivals = ref.watch(_festivalOptionsProvider).valueOrNull ?? [];
    final followedIds =
        ref.watch(_followedFestivalIdsProvider).valueOrNull ?? const {};

    if (festivals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final suggestions = festivals
        .where((f) => !followedIds.contains(f.id))
        .take(3)
        .toList();

    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? festivals
        : festivals
              .where((f) => f.name.toLowerCase().contains(normalizedQuery))
              .toList();
    final selectedFirst = [
      ...filtered.where((f) => followedIds.contains(f.id)),
      ...filtered.where((f) => !followedIds.contains(f.id)),
    ];

    return ListView(
      children: [
        if (suggestions.isNotEmpty) ...[
          Text(
            'Vorschläge',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final festival in suggestions)
                ActionChip(
                  avatar: Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: colors.accentPrimary,
                  ),
                  label: Text(festival.name),
                  onPressed: () => _toggle(festival.id, false),
                  backgroundColor: colors.accentPrimary.withValues(
                    alpha: 0.08,
                  ),
                  side: BorderSide(color: colors.accentPrimary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Suchen …',
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: colors.textTertiary,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            filled: true,
            fillColor: colors.backgroundPrimary,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              borderSide: BorderSide(color: colors.separator),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              borderSide: BorderSide(color: colors.separator),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final festival in selectedFirst)
              FilterChip(
                label: Text(festival.name),
                selected: followedIds.contains(festival.id),
                onSelected: (_) =>
                    _toggle(festival.id, followedIds.contains(festival.id)),
                selectedColor: colors.accentPrimary.withValues(alpha: 0.16),
                backgroundColor: colors.backgroundSecondary,
                side: BorderSide(
                  color: followedIds.contains(festival.id)
                      ? colors.accentPrimary
                      : colors.separator,
                ),
                labelStyle: TextStyle(
                  color: followedIds.contains(festival.id)
                      ? colors.accentPrimary
                      : colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ],
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

  // Fix: die fünf echten Spalten von notification_preferences (siehe
  // NotificationPreferenceKey in
  // core/notifications/notification_preferences_providers.dart) heißen ohne
  // "notify_"-Präfix — der bisherige Upsert schrieb auf nicht existierende
  // Spalten ('notify_new_matching_events' etc.) und wäre gegen das echte
  // Schema mit einem Postgres-Fehler fehlgeschlagen. Jetzt über denselben
  // Service wie die Profil-Einstellungen (notification_settings_screen.dart)
  // statt eines eigenen, abweichenden Upserts.
  Future<void> _savePreferences() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await Supabase.instance.client.from('notification_preferences').upsert({
      'user_id': userId,
      NotificationPreferenceKey.newMatchingEvents.column: _recommendations,
      NotificationPreferenceKey.priceChanges.column: _ticketAlerts,
      NotificationPreferenceKey.almostSoldOut.column: _almostSoldOut,
      NotificationPreferenceKey.followedEnsembleNewEvent.column:
          _followedArtists,
      NotificationPreferenceKey.reminderDayBefore.column:
          _savedEventReminders,
    }, onConflict: 'user_id');
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
            value: _followedArtists,
            onChanged: (value) => setState(() => _followedArtists = value),
            title: const Text('Neue Events gefolgter Profile'),
            subtitle: const Text(
              'Personen, Ensembles und Venues, denen du folgst.',
            ),
          ),
          SwitchListTile(
            value: _recommendations,
            onChanged: (value) => setState(() => _recommendations = value),
            title: const Text('Empfehlungen in deiner Nähe'),
          ),
          SwitchListTile(
            value: _ticketAlerts,
            onChanged: (value) => setState(() => _ticketAlerts = value),
            title: const Text('Preisänderungen'),
          ),
          SwitchListTile(
            value: _almostSoldOut,
            onChanged: (value) => setState(() => _almostSoldOut = value),
            title: const Text('Bald ausverkauft'),
          ),
          SwitchListTile(
            value: _savedEventReminders,
            onChanged: (value) => setState(() => _savedEventReminders = value),
            title: const Text('Erinnerungen an gespeicherte Events'),
          ),
          // Vorverkaufsstarts und eine wöchentliche Zusammenfassung sind Teil
          // der vom Nutzer vorgegebenen Zielstruktur, haben aber (noch)
          // keine eigene Spalte in notification_preferences — siehe PR-
          // Beschreibung. Bewusst kein neues Schema/keine Migration hierfür
          // erfunden, nur als offener Punkt dokumentiert.
        ],
      ),
    );
  }
}

/// Zeigt die gewählte Stadt für die Zusammenfassung — liest
/// profiles.preferred_region_id und löst den Namen über city_regions auf
/// (dieselbe View wie in _LocationStep, nur schreibend statt lesend anders
/// herum).
final _preferredCityNameProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final profileRow = await Supabase.instance.client
      .from('profiles')
      .select('preferred_region_id')
      .eq('id', user.id)
      .maybeSingle();
  final regionId = profileRow?['preferred_region_id'] as String?;
  if (regionId == null) return null;
  final cityRow = await Supabase.instance.client
      .from('city_regions')
      .select('name_de')
      .eq('id', regionId)
      .maybeSingle();
  return cityRow?['name_de'] as String?;
});

/// Schritt 8 aus dem Onboarding-Konzept: Zusammenfassung von Stadt,
/// Interessen, gefolgten Profilen (inkl. Schritt 6) und
/// Benachrichtigungseinstellungen — jede Zeile mit "Bearbeiten"-Link zurück
/// zum jeweiligen Schritt, statt nur eines Abschluss-Bildschirms ohne
/// Übersicht.
class _SummaryStep extends ConsumerWidget {
  const _SummaryStep({
    required this.onFinished,
    required this.onEditLocation,
    required this.onEditInterests,
    required this.onEditFollows,
    required this.onEditNotifications,
  });

  final VoidCallback onFinished;
  final VoidCallback onEditLocation;
  final VoidCallback onEditInterests;
  final VoidCallback onEditFollows;
  final VoidCallback onEditNotifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cityName = ref.watch(_preferredCityNameProvider).valueOrNull;
    final interests =
        ref.watch(userInterestsProvider).valueOrNull ?? UserInterests.empty;
    final follows = ref.watch(myFollowsProvider).valueOrNull ?? MyFollows.empty;
    final followedFestivals =
        ref.watch(_followedFestivalIdsProvider).valueOrNull ?? const {};
    final notifications = ref.watch(notificationPreferencesProvider).valueOrNull;

    final interestsCount =
        interests.genreIds.length +
        interests.personIds.length +
        interests.ensembleIds.length +
        interests.venueIds.length;
    final followedCount =
        follows.persons.length +
        follows.ensembles.length +
        follows.venues.length +
        followedFestivals.length;
    final activeNotificationsCount = notifications == null
        ? 0
        : [
            notifications.newMatchingEvents,
            notifications.priceChanges,
            notifications.almostSoldOut,
            notifications.reminderDayBefore,
            notifications.followedEnsembleNewEvent,
          ].where((enabled) => enabled).length;

    return _StepScaffold(
      title: 'Dein Profil ist eingerichtet',
      subtitle: 'Deine persönlichen Konzertempfehlungen sind jetzt bereit.',
      icon: Icons.check_circle_rounded,
      onPrimary: onFinished,
      primaryLabel: 'Konzerte für dich entdecken',
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.location_on_rounded,
            label: cityName ?? 'Keine Stadt ausgewählt',
            onEdit: onEditLocation,
          ),
          _SummaryRow(
            icon: Icons.interests_rounded,
            label: interestsCount == 0
                ? 'Keine Interessen ausgewählt'
                : '$interestsCount Interessen ausgewählt',
            onEdit: onEditInterests,
          ),
          _SummaryRow(
            icon: Icons.bookmark_added_rounded,
            label: followedCount == 0
                ? 'Niemandem gefolgt'
                : '$followedCount Profilen gefolgt',
            onEdit: onEditFollows,
          ),
          _SummaryRow(
            icon: Icons.notifications_active_rounded,
            label: '$activeNotificationsCount von 5 Benachrichtigungen aktiv',
            onEdit: onEditNotifications,
          ),
        ],
      ),
    );
  }
}

/// Eine Zeile der Zusammenfassung mit "Bearbeiten"-Link zurück zum
/// jeweiligen Schritt.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.onEdit,
  });

  final IconData icon;
  final String label;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.accentPrimary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          TextButton(onPressed: onEdit, child: const Text('Bearbeiten')),
        ],
      ),
    );
  }
}
