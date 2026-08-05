import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/onboarding/onboarding_status.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/interest_picker.dart';
import '../../../l10n/generated/app_localizations.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 4;

  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    await OnboardingStatus.markCompleted();

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _WelcomeStep(),
                  _InterestsStep(),
                  _LocationStep(),
                  _NotificationsStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPaddingMobile),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pageCount; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? colors.accentPrimary
                                : colors.separator,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(
                        _page == _pageCount - 1
                            ? l10n.onboardingGetStarted
                            : l10n.onboardingNext,
                      ),
                    ),
                  ),
                  if (_page > 0)
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        l10n.onboardingSkip,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
        ],
      ),
    );
  }
}

class _InterestsStep extends StatelessWidget {
  const _InterestsStep();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.onboardingInterestsTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.onboardingInterestsSubtitle,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.lg),
          const InterestPicker(),
        ],
      ),
    );
  }
}

class _LocationStep extends StatefulWidget {
  const _LocationStep();

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  bool _requesting = false;
  String? _status;

  Future<void> _requestLocation() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _requesting = true;
      _status = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _status = l10n.onboardingLocationDenied);
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _status = l10n.onboardingLocationServiceDisabled);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      await Supabase.instance.client.rpc(
        'update_home_location',
        params: {'p_lat': position.latitude, 'p_lng': position.longitude},
      );
      setState(() => _status = l10n.onboardingLocationSaved);
    } catch (_) {
      setState(() => _status = l10n.onboardingLocationFailed);
    } finally {
      if (mounted) setState(() => _requesting = false);
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
          Icon(
            Icons.location_on_rounded,
            size: 56,
            color: colors.accentPrimary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.onboardingLocationTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.onboardingLocationSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _requesting ? null : _requestLocation,
            icon: const Icon(Icons.my_location_rounded),
            label: Text(
              _requesting
                  ? l10n.onboardingLocationRequesting
                  : l10n.onboardingLocationShare,
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _status!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationsStep extends StatefulWidget {
  const _NotificationsStep();

  @override
  State<_NotificationsStep> createState() => _NotificationsStepState();
}

class _NotificationsStepState extends State<_NotificationsStep> {
  bool _requesting = false;
  bool _done = false;

  Future<void> _requestNotifications() async {
    setState(() => _requesting = true);
    await PushService.initialize();
    if (mounted) {
      setState(() {
        _requesting = false;
        _done = true;
      });
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
          Icon(
            Icons.notifications_active_rounded,
            size: 56,
            color: colors.accentPrimary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.onboardingNotificationsTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.onboardingNotificationsSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: _requesting || _done ? null : _requestNotifications,
            icon: Icon(
              _done ? Icons.check_rounded : Icons.notifications_rounded,
            ),
            label: Text(
              _done
                  ? l10n.onboardingNotificationsDone
                  : (_requesting
                        ? l10n.onboardingNotificationsRequesting
                        : l10n.onboardingNotificationsEnable),
            ),
          ),
        ],
      ),
    );
  }
}
