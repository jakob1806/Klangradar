import SwiftUI

/// Bettet die bestehende `InterestsView` (Features/Profile/InterestsView.swift)
/// als Onboarding-Schritt ein — deren `.navigationTitle` bleibt hier ohne
/// umgebenden NavigationStack einfach wirkungslos. Jede Auswahl wird von
/// InterestsView selbst sofort gespeichert, "Weiter" schließt nur den Schritt
/// ab, ohne selbst noch etwas zu sichern.
struct InterestsStepView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            InterestsView(auth: auth, repository: repository)
        }
        .navigationTitle("Was interessiert dich?")
        .onboardingChrome()
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: onFinished) { Text("Weiter").frame(maxWidth: .infinity) }
                    .authPrimaryButtonStyle().controlSize(.large)
                Button("Jetzt überspringen", action: onFinished)
                    .font(.footnote.weight(.medium))
            }
            .authBottomActionLayout()
        }
    }
}
