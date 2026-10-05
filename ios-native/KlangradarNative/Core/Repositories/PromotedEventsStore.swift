import Foundation

/// IDs der aktuell beworbenen Events (bezahlte, genehmigte Promotionen im
/// Buchungszeitraum). `EventArtwork` blendet für diese Events oben links ein
/// kleines "Anzeige"-Label ein — Werbung muss als solche erkennbar sein.
@MainActor
final class PromotedEventsStore: ObservableObject {
    static let shared = PromotedEventsStore()
    @Published private(set) var ids: Set<UUID> = []

    func load(client: SupabaseRESTClient?) async {
        guard let client else { return }
        // Fehler bewusst still: ohne Liste erscheint schlicht kein Label.
        guard let rows: [UUID] = try? await client.rpc("active_promoted_event_ids") else { return }
        ids = Set(rows)
    }
}
