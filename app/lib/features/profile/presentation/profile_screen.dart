import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/biometric_auth.dart';
import '../../../core/localization/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'widgets/admin_portal_dialog.dart';
import 'widgets/auth_section.dart';
import 'widgets/language_sheet.dart';
import 'widgets/profile_avatar_editor.dart';
import 'widgets/theme_mode_sheet.dart';

class _ProfileStats {
  const _ProfileStats({required this.visits, required this.followedPeople});
  final int visits;
  final int followedPeople;
  int get level => (1 + visits ~/ 3 + followedPeople ~/ 12).clamp(1, 50);
}

final _profileStatsProvider = FutureProvider.autoDispose<_ProfileStats>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isAnonymous) {
    return const _ProfileStats(visits: 0, followedPeople: 0);
  }
  final client = Supabase.instance.client;
  final results = await Future.wait<List<dynamic>>([
    client
        .from('coach_event_reflections')
        .select('event_id')
        .eq('user_id', user.id)
        .then((value) => value as List)
        .catchError((_) => <dynamic>[]),
    client
        .from('user_favorite_persons')
        .select('person_id')
        .eq('user_id', user.id)
        .then((value) => value as List)
        .catchError((_) => <dynamic>[]),
  ]);
  return _ProfileStats(
    visits: results[0].length,
    followedPeople: results[1].length,
  );
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final user = ref.watch(currentUserProvider);
    // isAnonymous: die Bootstrap-Session aus main.dart zählt hier nicht als
    // "angemeldet" — sonst sähe jeder Neuinstall sofort wie eingeloggt aus,
    // ohne dass je eine E-Mail oder Apple/Google-Login stattgefunden hätte.
    final isSignedIn = user != null && !user.isAnonymous;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPaddingMobile,
          vertical: AppSpacing.xl,
        ),
        children: [
          if (!isSignedIn)
            Card(
              elevation: 0,
              color: colors.glass,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: colors.separator),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AuthSection(
                  onSignedIn: () {
                    ref.invalidate(authStateChangesProvider);
                    ref.invalidate(currentUserProvider);
                  },
                  onCreateAccount: () =>
                      context.push('/onboarding?create=true'),
                ),
              ),
            )
          else
            _SignedInHeader(
              userId: user.id,
              email: user.email ?? l10n.profileSignedIn,
              colors: colors,
            ),
          const SizedBox(height: AppSpacing.xxl),
          _ProfileRow(
            label: 'Klangradar Coach',
            colors: colors,
            onTap: () => context.push('/coach'),
          ),
          _ProfileRow(
            label: l10n.profileMyFavorites,
            colors: colors,
            onTap: () => context.push('/favorites'),
          ),
          _ProfileRow(
            label: l10n.profileMyFollows,
            colors: colors,
            onTap: () => context.push('/follows'),
          ),
          _ProfileRow(
            label: l10n.profileInterests,
            colors: colors,
            onTap: () => context.push('/interests'),
          ),
          _ProfileRow(
            label: l10n.profileNotifications,
            colors: colors,
            onTap: () => context.push('/notification-settings'),
          ),
          _ProfileRow(
            label: l10n.profileMyLists,
            colors: colors,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.profileMyListsComingSoon)),
            ),
          ),
          _ProfileRow(
            label: l10n.profileAppearance,
            colors: colors,
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (_) =>
                  ThemeModeSheet(current: ref.read(themeModeProvider)),
            ),
          ),
          _ProfileRow(
            label: AppLocalizations.of(context)!.profileLanguage,
            colors: colors,
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (_) => LanguageSheet(current: ref.read(localeProvider)),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: TextButton(
              onPressed: () => showAdminPortalDialog(context),
              child: Text(
                l10n.profileAdminPortal,
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedInHeader extends ConsumerWidget {
  const _SignedInHeader({
    required this.userId,
    required this.email,
    required this.colors,
  });
  final String userId;
  final String email;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats =
        ref.watch(_profileStatsProvider).valueOrNull ??
        const _ProfileStats(visits: 0, followedPeople: 0);
    return Column(
      children: [
        ProfileAvatarEditor(userId: userId),
        const SizedBox(height: AppSpacing.sm),
        Text(
          email,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _ProfileMetric(
                value: stats.visits,
                label: 'Besuche',
                icon: Icons.confirmation_num_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _VisitsDetailScreen(userId: userId),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _ProfileMetric(
                value: stats.followedPeople,
                label: 'Gefolgt',
                icon: Icons.people_alt_rounded,
                onTap: () => context.push('/follows'),
              ),
            ),
            Expanded(
              child: _ProfileMetric(
                value: stats.level,
                label: 'Level',
                icon: Icons.workspace_premium_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _LevelDetailScreen(stats: stats),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: () => _showEditProfile(context),
          child: const Text('Profil bearbeiten'),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _FaceIdToggle(),
        TextButton(
          onPressed: AuthService.signOut,
          child: Text(
            AppLocalizations.of(context)!.profileSignOut,
            style: TextStyle(color: colors.error),
          ),
        ),
      ],
    );
  }

  void _showEditProfile(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profilbild kannst du direkt oben bearbeiten.'),
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final int value;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Icon(icon, size: 16, color: context.appColors.accentPrimary),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

class _VisitsDetailScreen extends StatelessWidget {
  const _VisitsDetailScreen({required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Besuchte Konzerte')),
    body: FutureBuilder<List<dynamic>>(
      future: Supabase.instance.client
          .from('coach_event_reflections')
          .select('attended_at, events(title, venues(name))')
          .eq('user_id', userId)
          .order('attended_at', ascending: false),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <dynamic>[];
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (rows.isEmpty)
          return const Center(child: Text('Noch keine besuchten Konzerte.'));
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final row = rows[index] as Map<String, dynamic>;
            final event = row['events'] as Map<String, dynamic>?;
            final venue = event?['venues'] as Map<String, dynamic>?;
            return ListTile(
              title: Text(event?['title'] as String? ?? 'Konzert'),
              subtitle: Text(venue?['name'] as String? ?? 'Ort folgt'),
            );
          },
        );
      },
    ),
  );
}

class _LevelDetailScreen extends StatelessWidget {
  const _LevelDetailScreen({required this.stats});
  final _ProfileStats stats;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dein Level')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              size: 64,
              color: context.appColors.accentPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              'Level ${stats.level}',
              style: Theme.of(
                context,
              ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dein Level wächst mit besuchten Konzerten und den Künstler:innen, denen du folgst.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Face ID/Touch ID zum optionalen Schutz des Accounts (Nutzerwunsch) — nur
/// als Einstellungs-Toggle, keine App-Start-Sperre (analog zum
/// ios-native-Umsetzungsstand, siehe dortige MIGRATION_STATUS.md).
class _FaceIdToggle extends StatefulWidget {
  const _FaceIdToggle();

  @override
  State<_FaceIdToggle> createState() => _FaceIdToggleState();
}

class _FaceIdToggleState extends State<_FaceIdToggle> {
  bool _available = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await BiometricAuth.isAvailable;
    final enabled = await BiometricAuth.isEnabled;
    if (mounted) {
      setState(() {
        _available = available;
        _enabled = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return SwitchListTile(
      title: const Text('Face ID zum Schutz nutzen'),
      value: _enabled,
      onChanged: (value) async {
        setState(() => _enabled = value);
        await BiometricAuth.setEnabled(value);
      },
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.colors, this.onTap});
  final String label;
  final AppColorsExtension colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.separator)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
