import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../theme/app_colors.dart';

/// Folgen-Button für Festivals — Empfehlungssystem-Anfrage (Punkt 25,
/// "Folgen als Kernfeature": Personen/Ensembles/Venues/Festivals). Eigenes
/// kleines Widget statt einer Erweiterung von [InterestCategory]: das
/// bestehende Enum wird an vielen Stellen exhaustiv geswitcht (Picker,
/// Notify-Button, Gefolgt-Übersicht), Festivals haben keinen eigenen
/// Detail-Screen und tauchen nur in dieser einen Home-Kachel auf — eine
/// eigenständige, isolierte Implementierung ist hier das kleinere Risiko.
final festivalFollowProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  festivalId,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final row = await Supabase.instance.client
      .from('user_favorite_festivals')
      .select('festival_id')
      .eq('user_id', user.id)
      .eq('festival_id', festivalId)
      .maybeSingle();
  return row != null;
});

class FestivalFollowButton extends ConsumerWidget {
  const FestivalFollowButton({required this.festivalId, super.key});

  final String festivalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.appColors;
    final followingAsync = ref.watch(festivalFollowProvider(festivalId));
    final isFollowing = followingAsync.valueOrNull ?? false;

    Future<void> handleTap() async {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.followSignInPrompt)));
        return;
      }
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
      ref.invalidate(festivalFollowProvider(festivalId));
    }

    return TextButton.icon(
      onPressed: handleTap,
      icon: Icon(
        isFollowing
            ? Icons.bookmark_added_rounded
            : Icons.bookmark_add_outlined,
        size: 18,
        color: isFollowing ? colors.accentPrimary : colors.textSecondary,
      ),
      label: Text(
        isFollowing ? l10n.followLabelActive : l10n.followLabelInactive,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isFollowing ? colors.accentPrimary : colors.textSecondary,
        ),
      ),
    );
  }
}
