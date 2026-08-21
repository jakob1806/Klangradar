import SwiftUI

/// Zentraler Login für Onboarding und Profil. E-Mail-Codes werden hier
/// bewusst nicht angeboten: Codes bestätigen nur neue E-Mail-Adressen,
/// Recovery erfolgt ausschließlich über einen sicheren Link.
struct PasswordLoginView: View {
    @ObservedObject var auth: AuthStore
    var repository: UserRepository?
    var onSignedIn: () -> Void = {}
    var onCreatedAccount: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsForgotPassword = false
    @State private var showsSignUp = false
    @State private var showsBiometricOffer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            KlangradarAppIcon(size: 72)
                            Text("Willkommen zurück")
                                .font(.title2.bold())
                            Text("Melde dich an, um deine Favoriten und Empfehlungen auf allen Geräten zu sehen.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("E-Mail-Adresse", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { if canLogIn { Task { await login() } } }
                }

                Section {
                    Button("Passwort vergessen?") { showsForgotPassword = true }
                        .disabled(isWorking)
                } footer: {
                    Text("Du erhältst einen sicheren Link, mit dem du ein neues Passwort festlegen kannst.")
                }

                if auth.isAppleSignInAvailable || auth.isGoogleSignInAvailable {
                    Section("Andere Anmeldeoptionen") {
                    if auth.isAppleSignInAvailable {
                        Button {
                            Task { await oauth(provider: "Apple") { try await auth.signInWithApple() } }
                        } label: {
                            Label("Mit Apple anmelden", systemImage: "apple.logo")
                        }
                        .disabled(isWorking)
                    }

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

                Section {
                    Button("Neuen Account erstellen") { showsSignUp = true }
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { Task { await login() } } label: {
                    Text("Anmelden").frame(maxWidth: .infinity)
                }
                    .authPrimaryButtonStyle()
                    .controlSize(.large)
                    .disabled(!canLogIn)
                    .authBottomActionLayout()
            }
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
            .sheet(isPresented: $showsForgotPassword) {
                ForgotPasswordView(auth: auth)
            }
            .sheet(isPresented: $showsSignUp) {
                AccountCreationView(auth: auth, repository: repository) {
                    showsSignUp = false
                    (onCreatedAccount ?? onSignedIn)()
                    dismiss()
                }
            }
            .onChange(of: auth.isCompletingPasswordRecovery) { _, isRecovering in
                if isRecovering { dismiss() }
            }
            .alert(biometricOfferTitle, isPresented: $showsBiometricOffer) {
                Button("Aktivieren") {
                    UserDefaults.standard.set(true, forKey: BiometricAuth.enabledStorageKey)
                    finishSignIn()
                }
                Button("Später", role: .cancel, action: finishSignIn)
            } message: {
                Text("Schütze deine gespeicherte Anmeldung auf diesem Gerät. Dein Passwort wird weiterhin sicher in der Sitzung verwaltet.")
            }
        }
    }

    private var canLogIn: Bool {
        !isWorking
            && email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
            && !password.isEmpty
    }

    private func login() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.signInWithPassword(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password
            )
            completeSignIn()
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
            completeSignIn()
        } catch {
            errorMessage = "\(provider): \(error.localizedDescription)"
        }
    }

    private var biometricOfferTitle: String {
        BiometricAuth.availableBiometryKind == .touchID ? "Touch ID aktivieren?" : "Face ID aktivieren?"
    }

    private func completeSignIn() {
        if BiometricAuth.availableBiometryKind != .none, !BiometricAuth.isEnabled {
            showsBiometricOffer = true
        } else {
            finishSignIn()
        }
    }

    private func finishSignIn() {
        onSignedIn()
        dismiss()
    }
}

private struct AccountCreationView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email: String?
    @State private var marketingEmailOptIn = false

    var body: some View {
        NavigationStack {
            Group {
                if let email {
                    VerifyEmailStepView(
                        auth: auth,
                        repository: repository,
                        email: email,
                        marketingEmailOptIn: marketingEmailOptIn,
                        onVerified: onFinished,
                        onChangeEmail: { self.email = nil }
                    )
                } else {
                    SignUpStepView(auth: auth) { newEmail, optIn in
                        email = newEmail
                        marketingEmailOptIn = optIn
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
