import Foundation

/// Schreibt Event-Aufrufe (`event_views`) und Ticket-Klicks (`ticket_clicks`)
/// — wie die Flutter-App. Grundlage für Empfehlungen, die Veranstalter-
/// Kennzahlen und die Wirkungsstatistik bezahlter Promotionen. Vorher
/// protokollierte die iOS-App nichts, dort blieben alle Werte bei null.
/// Fire-and-forget: Fehler (offline, keine Session) werden ignoriert.
@MainActor
final class EngagementLogger {
    static let shared = EngagementLogger()
    private var client: SupabaseRESTClient?
    private weak var auth: AuthStore?
    private var lastView: (id: UUID, at: Date)?

    func configure(client: SupabaseRESTClient?, auth: AuthStore) {
        self.client = client
        self.auth = auth
    }

    func logView(eventID: UUID) {
        // Doppelte Zählung beim schnellen Zurück/Vor vermeiden.
        if let lastView, lastView.id == eventID, Date.now.timeIntervalSince(lastView.at) < 30 { return }
        lastView = (eventID, .now)
        insert(table: "event_views", eventID: eventID)
    }

    func logTicketClick(eventID: UUID) {
        insert(table: "ticket_clicks", eventID: eventID)
    }

    private func insert(table: String, eventID: UUID) {
        guard let client, let session = auth?.session else { return }
        let values: JSONObject = ["user_id": .string(session.user.id.uuidString.lowercased()), "event_id": .string(eventID.uuidString.lowercased())]
        let token = session.accessToken
        Task.detached {
            _ = try? await client.insert(table: table, values: values, accessToken: token)
        }
    }
}
