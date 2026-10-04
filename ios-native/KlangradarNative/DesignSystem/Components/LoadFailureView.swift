import SwiftUI

/// Gemeinsamer Fehlerzustand mit Wiederholen-Button. Ersetzt das stille
/// Verschlucken von Netzwerkfehlern (`try?` -> leere Liste), bei dem Nutzer
/// "keine Konzerte" statt "keine Verbindung" sahen.
struct LoadFailureView: View {
    var title = "Konnte nicht geladen werden"
    var message = "Bitte prüfe deine Internetverbindung und versuche es erneut."
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Erneut versuchen", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
