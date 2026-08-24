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

    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Verpasse keine interessanten Konzerte").font(.title2.bold())
                Text("Wähle zuerst aus, was dich interessiert. Den iOS-Systemdialog öffnen wir erst danach.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            NotificationSettingsView(auth: auth, repository: repository)
        }
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button { Task { await requestPermission() } } label: {
                    Text("Benachrichtigungen aktivieren").frame(maxWidth: .infinity)
                }
                .authPrimaryButtonStyle().controlSize(.large).disabled(isWorking)
                Button("Nicht jetzt", action: onFinished).font(.footnote.weight(.medium)).disabled(isWorking)
            }
            .authBottomActionLayout()
        }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
    }

    private func requestPermission() async {
        isWorking = true
        defer { isWorking = false }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        onFinished()
    }
}
