import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("didCompleteOnboarding") private var didComplete = false
    @State private var page = 0

    private let pages = [
        ("Klangradar", "Finde klassische Konzerte, Künstler:innen und Spielstätten in München.", "waveform.circle"),
        ("Dein Programm", "Wähle später Genres, Personen, Ensembles und Orte – Klangradar nutzt sie für passendere Empfehlungen.", "sparkles"),
        ("Nichts verpassen", "Aktiviere auf Wunsch Hinweise zu neuen Terminen, Preisänderungen und knappen Tickets.", "bell.badge")
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: pages[page].2).font(.system(size: 76)).foregroundStyle(KlangradarTheme.accent).contentTransition(.symbolEffect(.replace))
            VStack(spacing: 12) { Text(pages[page].0).font(.largeTitle.bold()); Text(pages[page].1).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Spacer()
            HStack { ForEach(pages.indices, id: \.self) { Circle().fill($0 == page ? KlangradarTheme.accent : Color.secondary.opacity(0.25)).frame(width: 8, height: 8) } }
            Button(page == pages.count - 1 ? "Klangradar starten" : "Weiter") { advance() }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            if page == pages.count - 1 { Button("Ohne Benachrichtigungen fortfahren") { complete() }.font(.footnote) }
        }
        .padding(32)
        .interactiveDismissDisabled()
    }

    private func advance() {
        if page < pages.count - 1 { withAnimation { page += 1 } }
        else { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]); await MainActor.run { complete() } } }
    }
    private func complete() { didComplete = true; dismiss() }
}
