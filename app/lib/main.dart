import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/localization/locale_provider.dart';
import 'core/onboarding/onboarding_status.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/time/munich_time.dart';
import 'firebase_options.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MunichTime.initialize();

  await Env.load();
  await initializeDateFormatting('de_DE', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );

    // Jede Session braucht einen profiles-Datensatz — Favoriten, Interessen
    // und Benachrichtigungseinstellungen hängen alle an user_id, was ohne
    // irgendeine Session (auch ohne echten Login) nie der Fall wäre. Scheitert
    // das offline beim allerersten Start, bleibt die App nutzbar, nur ohne
    // Personalisierung bis zum nächsten Start mit Netz.
    if (Supabase.instance.client.auth.currentUser == null) {
      try {
        await Supabase.instance.client.auth.signInAnonymously();
      } catch (_) {}
    }
  }

  // Wiederkehrende, bereits *echt* eingeloggte Nutzer bekommen Push direkt
  // beim Start registriert. Erstanmeldung stößt das stattdessen über den
  // Auth-State-Listener in KlassikMuenchenApp an, sobald der Login
  // tatsächlich abgeschlossen ist (relevant v.a. für OAuth, das über einen
  // externen Browser läuft und nicht synchron zurückkehrt); die anonyme
  // Bootstrap-Session oben triggert das bewusst nicht — Berechtigung wird
  // erst im Onboarding-Flow bzw. beim ersten echten Login abgefragt.
  final startupUser = Supabase.instance.client.auth.currentUser;
  if (startupUser != null && !startupUser.isAnonymous) {
    unawaited(PushService.initialize());
  }

  final onboardingDone = await OnboardingStatus.isCompleted();

  runApp(
    ProviderScope(
      child: KlassikMuenchenApp(
        initialLocation: onboardingDone ? '/home' : '/onboarding',
      ),
    ),
  );
}

class KlassikMuenchenApp extends ConsumerStatefulWidget {
  const KlassikMuenchenApp({super.key, this.initialLocation = '/home'});

  final String initialLocation;

  @override
  ConsumerState<KlassikMuenchenApp> createState() => _KlassikMuenchenAppState();
}

class _KlassikMuenchenAppState extends ConsumerState<KlassikMuenchenApp> {
  StreamSubscription<AuthState>? _authSubscription;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildAppRouter(initialLocation: widget.initialLocation);
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((data) {
            if (data.event == AuthChangeEvent.signedIn) {
              PushService.initialize();
            }
            if (data.event == AuthChangeEvent.passwordRecovery) {
              _router.go('/reset-password');
            }
          });
    } catch (_) {
      // Supabase wurde nicht initialisiert (z. B. in Widget-Tests ohne main()) — kein Push-Setup nötig.
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Klangradar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: _router,
      // null = Systemsprache folgen (nur wenn der Nutzer das im Profil
      // explizit gewählt hat, siehe locale_provider.dart) — MaterialApp
      // wählt dann selbst aus supportedLocales anhand des Geräts.
      locale: ref.watch(localeProvider),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
