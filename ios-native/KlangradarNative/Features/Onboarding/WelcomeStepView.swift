import SwiftUI

/// Einstiegs-Schritt: Anmelden (bestehender Account) / Account erstellen /
/// ohne Account fortfahren (Gast, bleibt auf der anonymen Bootstrap-Session
/// aus main.dart-Äquivalent AppEnvironment).
struct WelcomeStepView: View {
    @ObservedObject var auth: AuthStore
    let onCreateAccount: () -> Void
    let onLogIn: () -> Void
    let onContinueAsGuest: () -> Void
    let onAuthenticated: () -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 20) {
                KlangradarAppIcon(size: 88)
                Text("Willkommen bei Klangradar")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Entdecke Konzerte, Künstler:innen und Spielstätten in deiner Nähe.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                Button(action: onLogIn) {
                    Text("Anmelden").frame(maxWidth: .infinity)
                }
                    .authPrimaryButtonStyle()
                    .controlSize(.large)
                Button(action: onCreateAccount) {
                    Text("Konto erstellen").frame(maxWidth: .infinity)
                }
                    .authSecondaryButtonStyle()
                    .controlSize(.large)
                Button("Ohne Account fortfahren", action: onContinueAsGuest)
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                if auth.isAppleSignInAvailable || auth.isGoogleSignInAvailable {
                    HStack { Rectangle().frame(height: 0.5); Text("oder").font(.caption); Rectangle().frame(height: 0.5) }
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
                if auth.isAppleSignInAvailable {
                    Button { Task { await oauth { try await auth.signInWithApple() } } } label: {
                        Label("Mit Apple anmelden", systemImage: "apple.logo").frame(maxWidth: .infinity)
                    }
                    .authSecondaryButtonStyle()
                    .controlSize(.large)
                    .disabled(isWorking)
                }
                if auth.isGoogleSignInAvailable {
                    Button { Task { await oauth { try await auth.signInWithGoogle() } } } label: {
                        GoogleSignInLabel().frame(maxWidth: .infinity)
                    }
                    .authSecondaryButtonStyle()
                    .controlSize(.large)
                    .disabled(isWorking)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .navigationBarBackButtonHidden()
        .onboardingChrome()
        .background { KlangradarBackground().ignoresSafeArea() }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
    }

    private func oauth(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await action()
            onAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
