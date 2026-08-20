import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Nicht interessiert"/Ausblenden (Empfehlungssystem-Anfrage, Abschnitt 4:
/// harter Ausschluss statt nur Malus). Vier Entitätstypen, siehe
/// content_dismissals in
/// backend/supabase/migrations/20261016000012_recommendation_phase1_signals.sql
/// — bewusst getrennt vom bestehenden content_reports (Datenqualitäts-
/// Meldungen mit festem Grund-Katalog): hier geht es um reine Präferenz.
enum DismissEntityType { event, venue, person, ensemble }

/// IDs, die in dieser App-Sitzung ausgeblendet wurden — rein clientseitiger
/// Filter, den event_section.dart & Co. sofort beim Ausblenden anwenden.
/// Vorher löste jedes Ausblenden ein ref.invalidate(homeDataProvider) aus,
/// das den kompletten 12-Request-Home-Feed neu lud, nur um eine Karte
/// verschwinden zu lassen (Perf-Audit: sichtbares Ruckeln). Die serverseitige
/// Eligibility-Filterung in recommended_events()/discovery_events()/
/// entity_news_events() sorgt ohnehin dafür, dass ein echter Neuladen (Pull-
/// to-Refresh, App-Neustart) das ausgeblendete Element korrekt weglässt —
/// dieser Client-Filter überbrückt nur die laufende Sitzung.
final dismissedEntityIdsProvider = StateProvider<Set<String>>((ref) => {});

extension on DismissEntityType {
  String get wireValue => switch (this) {
    DismissEntityType.event => 'event',
    DismissEntityType.venue => 'venue',
    DismissEntityType.person => 'person',
    DismissEntityType.ensemble => 'ensemble',
  };
}

class DismissalService {
  const DismissalService._();

  static Future<void> dismiss(
    WidgetRef ref, {
    required DismissEntityType entityType,
    required String entityId,
    String? reason,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Sofort clientseitig ausblenden, nicht erst nach dem Netzwerk-Write —
    // die Karte verschwindet ohne wahrnehmbare Verzögerung.
    ref.read(dismissedEntityIdsProvider.notifier).update(
      (ids) => {...ids, entityId},
    );

    await Supabase.instance.client.from('content_dismissals').upsert({
      'user_id': user.id,
      'entity_type': entityType.wireValue,
      'entity_id': entityId,
      if (reason != null) 'reason': reason,
    }, onConflict: 'user_id,entity_type,entity_id');
  }

  static Future<void> undo(
    WidgetRef ref, {
    required DismissEntityType entityType,
    required String entityId,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    ref.read(dismissedEntityIdsProvider.notifier).update(
      (ids) => {...ids}..remove(entityId),
    );

    await Supabase.instance.client
        .from('content_dismissals')
        .delete()
        .eq('user_id', user.id)
        .eq('entity_type', entityType.wireValue)
        .eq('entity_id', entityId);
  }
}
