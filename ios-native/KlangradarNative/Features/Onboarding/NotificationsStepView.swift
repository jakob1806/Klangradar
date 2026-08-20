import SwiftUI
import UserNotifications

/// Schritt "Benachrichtigungen": erst ein Erklär-Screen, dann erst der
/// iOS-Systemdialog (bessere Annahmequote als ein blinder Dialog beim
/// App-Start) — danach die bestehenden granularen Toggles
/// (Features/Profile/NotificationSettingsView.swift), unabhängig vom
/// Systemdialog-Ergebnis erreichbar: die Datenbank-Präferenzen bestimmen nur,
/// WELCHE Kategorien gesendet werden, falls die OS-Berechtigung überhaupt
/// erteilt ist.
struct NotificationsStepView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onFinished: () -> Void

    @State private var didRequestPermission = false
    @State private var isWorking = false

    var body: some View {
        if didRequestPermission {
            VStack(spacing: 0) {
                Text("Was möchtest du erfahren?")
                    .font(.title.bold())
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                NotificationSettingsView(auth: auth, repository: repository)
                Button("Weiter") { onFinished() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
        } else {
            OnboardingStepScaffold(
                title: "Nichts verpassen",
                subtitle: "Aktiviere Hinweise zu neuen Terminen gefolgter Künstler:innen, Preisänderungen und knappen Tickets.",
                systemImage: "bell.badge",
                content: { EmptyView() },
                primaryTitle: "Benachrichtigungen aktivieren",
                onPrimary: { Task { await requestPermission() } },
                secondaryTitle: "Ohne Benachrichtigungen fortfahren",
                onSecondary: { didRequestPermission = true },
                isWorking: isWorking
            )
        }
    }

    private func requestPermission() async {
        isWorking = true
        defer { isWorking = false }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        didRequestPermission = true
    }
}
