import SwiftUI

/// Meldungen-Tab — Platzhalter für Phase 1. Die echte Nutzerberichte-Inbox
/// (Status Neu/In Bearbeitung/Erledigt, gemeldeter vs. aktueller Wert,
/// Übernehmen/Ablehnen) folgt in Phase 3 inklusive der dafür nötigen
/// Migration auf content_reports.
struct EditorialReportsTabView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nutzerberichte-Inbox folgt",
                systemImage: "tray.full",
                description: Text("Gemeldete Inhalte werden hier in einer späteren Ausbaustufe zur Prüfung angezeigt.")
            )
            .navigationTitle("Meldungen")
            .editorialGlobalToolbar(auth: auth, repository: repository)
        }
    }
}
