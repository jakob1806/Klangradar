import SwiftUI

/// Ersetzt die frühere `EmailCodeLoginView` als primäre Anmeldeoberfläche —
/// Passwort statt E-Mail-Code (Nutzer-Entscheidung: OTP bleibt intern nur
/// für E-Mail-Bestätigung/Passwort-Reset). Wird sowohl vom Profil-Tab
/// (bestehender Login-Button) als auch vom Onboarding ("Anmelden" auf dem
/// Einstiegs-Screen für wiederkehrende Nutzer) als Sheet präsentiert.
///
/// Nutzt bewusst dieselbe schlichte VStack/`.roundedBorder`/
/// `.borderedProminent`-Sprache wie `WelcomeStepView`/`SignUpStepView` im
/// Onboarding, statt eines System-`Form` — vorher sah dieser Screen mit
/// seinen grauen Listenzeilen sichtbar anders aus als der Rest der App.
struct PasswordLoginView: View {
    @ObservedObject var auth: AuthStore
    var onSignedIn: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsForgotPassword = false

    private var isValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        TextField("E-Mail-Adresse", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        SecureField("Passwort", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: 12) {
                        Button("Anmelden") { Task { await login() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(isWorking || !isValid)
                        Button("Passwort vergessen?") { showsForgotPassword = true }
                            .font(.footnote)
                            .disabled(isWorking)
                    }

                    if isWorking {
                        ProgressView()
                    }

                    oauthSection
                }
                .padding(24)
            }
            .navigationTitle("Anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
            .sheet(isPresented: $showsForgotPassword) {
                ForgotPasswordView(auth: auth)
            }
        }
    }

    @ViewBuilder
    private var oauthSection: some View {
        if auth.isAppleSignInAvailable || auth.isGoogleSignInAvailable {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    line
                    Text("Oder anmelden mit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    line
                }

                if auth.isAppleSignInAvailable {
                    Button {
                        Task { await oauth(provider: "Apple") { try await auth.signInWithApple() } }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                            Text("Mit Apple anmelden")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isWorking)
                }

                if auth.isGoogleSignInAvailable {
                    Button {
                        Task { await oauth(provider: "Google") { try await auth.signInWithGoogle() } }
                    } label: {
                        HStack(spacing: 8) {
                            GoogleLogoView()
                                .frame(width: 18, height: 18)
                            Text("Mit Google anmelden")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isWorking)
                }
            }
        }
    }

    private var line: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
    }

    private func login() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.signInWithPassword(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            onSignedIn()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func oauth(provider: String, action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await action()
            onSignedIn()
            dismiss()
        } catch {
            errorMessage = "\(provider): \(error.localizedDescription)"
        }
    }
}
