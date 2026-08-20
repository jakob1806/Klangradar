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
            VStack(spacing: 6) {
                Text("Deine Interessen")
                    .font(.title.bold())
                Text("Genres, Künstler:innen, Ensembles und Orte — für passendere Empfehlungen. Kann jederzeit im Profil geändert werden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            InterestsView(auth: auth, repository: repository)

            Button("Weiter") { onFinished() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
        }
    }
}
