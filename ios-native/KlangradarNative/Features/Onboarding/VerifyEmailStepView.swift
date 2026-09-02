import SwiftUI

/// Schritt "E-Mail-Adresse per Code bestätigen". Erst danach existiert eine
/// echte (nicht-anonyme) Session — deshalb wird die AGB/Datenschutz-
/// Zustimmung aus dem Signup-Schritt hier (mit gültigem Access-Token)
/// als `terms_accepted_at`/`terms_version` nachgetragen.
struct VerifyEmailStepView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let email: String
    let marketingEmailOptIn: Bool
    let onVerified: () -> Void
    var onChangeEmail: (() -> Void)?

    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didResend = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(KlangradarTheme.accent)
                    Text("Wir haben einen sechsstelligen Code an **\(email)** gesendet.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                TextField("6-stelliger Code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                    }
            }

            Section {
                Button(didResend ? "Neuer Code wurde gesendet" : "Code erneut senden") {
                    Task { await resend() }
                }
                .disabled(isWorking || didResend)
                if let onChangeEmail {
                    Button("Andere E-Mail-Adresse verwenden", action: onChangeEmail)
                        .disabled(isWorking)
                }
            } footer: {
                Text("Der Code ist 60 Minuten gültig. Prüfe auch deinen Spam-Ordner.")
            }

            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .navigationTitle("E-Mail bestätigen")
        .onboardingChrome()
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await verify() } } label: {
                Text("E-Mail bestätigen").frame(maxWidth: .infinity)
            }
                .authPrimaryButtonStyle()
                .controlSize(.large)
                .disabled(code.count != 6 || isWorking)
                .authBottomActionLayout()
        }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .interactiveDismissDisabled(isWorking)
    }

    private func verify() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.verifySignupCode(code, email: email)
            if let repository, let userID = auth.userID, let token = auth.accessToken {
                try? await repository.acceptTerms(
                    version: "v1",
                    marketingEmailOptIn: marketingEmailOptIn,
                    userID: userID,
                    token: token
                )
            }
            onVerified()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resend() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.resendSignupConfirmation(email: email)
            didResend = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
