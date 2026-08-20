import SwiftUI

/// Ersetzt die frühere `EmailCodeLoginView` als primäre Anmeldeoberfläche —
/// Passwort statt E-Mail-Code (Nutzer-Entscheidung: OTP bleibt intern nur
/// für E-Mail-Bestätigung/Passwort-Reset). Wird sowohl vom Profil-Tab
/// (bestehender Login-Button) als auch vom Onboarding ("Anmelden" auf dem
/// Einstiegs-Screen für wiederkehrende Nutzer) als Sheet präsentiert.
struct PasswordLoginView: View {
    @ObservedObject var auth: AuthStore
    var onSignedIn: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsForgotPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-Mail-Adresse", text: $email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Anmelden") { Task { await login() } }
                        .disabled(
                            isWorking
                                || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || password.isEmpty
                        )
                    Button("Passwort vergessen?") { showsForgotPassword = true }
                        .font(.footnote)
                        .disabled(isWorking)
                }

                Section("Oder anmelden mit") {
                    Button {
                        Task { await oauth(provider: "Apple") { try await auth.signInWithApple() } }
                    } label: {
                        Label("Mit Apple anmelden", systemImage: "apple.logo")
                    }
                    .disabled(isWorking)

                    if auth.isGoogleSignInAvailable {
                        Button {
                            Task { await oauth(provider: "Google") { try await auth.signInWithGoogle() } }
                        } label: {
                            Label("Mit Google anmelden", systemImage: "g.circle.fill")
                        }
                        .disabled(isWorking)
                    }
                }
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
