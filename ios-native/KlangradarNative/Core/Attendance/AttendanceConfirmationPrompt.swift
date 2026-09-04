import SwiftUI

/// Eigenes Popup für die passive, standortbasierte Besuchs-Erkennung
/// (siehe AttendanceLocationMonitor) — erscheint, wenn die Nutzerin während
/// der Zeit eines gemerkten Konzerts an dessen Spielstätte war, entweder
/// direkt (App im Vordergrund) oder nach Antippen der Benachrichtigung.
/// Ausdrücklich getrennt vom direkten "Als besucht markieren"-Button in
/// EventDetailView, der ohne jede Standortprüfung sofort wirkt.
struct AttendanceConfirmationPrompt: View {
    let eventTitle: String
    let onAnswer: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(KlangradarTheme.accent)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text("Warst du hier?")
                    .font(.title3.bold())
                Text("Wir haben erkannt, dass du gerade bei „\(eventTitle)“ sein könntest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    onAnswer(true)
                    dismiss()
                } label: {
                    Text("Ja, als besucht markieren").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onAnswer(false)
                    dismiss()
                } label: {
                    Text("Nein").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(24)
        .presentationDragIndicator(.visible)
    }
}
