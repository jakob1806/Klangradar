import SwiftUI

/// Einstiegs-Schritt: Anmelden (bestehender Account) / Account erstellen /
/// ohne Account fortfahren (Gast, bleibt auf der anonymen Bootstrap-Session
/// aus main.dart-Äquivalent AppEnvironment).
struct WelcomeStepView: View {
    let onCreateAccount: () -> Void
    let onLogIn: () -> Void
    let onContinueAsGuest: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            Image(systemName: "waveform.circle")
                .font(.system(size: 76))
                .foregroundStyle(KlangradarTheme.accent)
            VStack(spacing: 12) {
                Text("Willkommen bei Klangradar")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Finde klassische Konzerte, Künstler:innen und Spielstätten in München.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 8)
            VStack(spacing: 12) {
                Button("Account erstellen") { onCreateAccount() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Anmelden") { onLogIn() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button("Ohne Account fortfahren") { onContinueAsGuest() }
                    .font(.footnote)
                    .padding(.top, 4)
            }
        }
        .padding(28)
    }
}
