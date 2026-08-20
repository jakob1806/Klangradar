import SwiftUI

/// Schritt "E-Mail-Adresse per Code bestätigen". Erst danach existiert eine
/// echte (nicht-anonyme) Session — deshalb wird die AGB/Datenschutz-
/// Zustimmung aus dem Signup-Schritt hier (mit gültigem Access-Token)
/// als `terms_accepted_at`/`terms_version` nachgetragen.
struct VerifyEmailStepView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let email: String
    let onVerified: () -> Void

    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didResend = false

    var body: some View {
        OnboardingStepScaffold(
            title: "E-Mail bestätigen",
            subtitle: "Wir haben einen Code an \(email) geschickt.",
            systemImage: "envelope.badge.shield.half.filled",
            content: {
                VStack(spacing: 10) {
                    TextField("Bestätigungscode", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                    Button(didResend ? "Code erneut verschickt" : "Code erneut senden") {
                        Task { await resend() }
                    }
                    .font(.footnote)
                    .disabled(isWorking || didResend)
                }
            },
            primaryTitle: "Bestätigen",
            isPrimaryEnabled: !code.isEmpty,
            onPrimary: { Task { await verify() } },
            errorMessage: errorMessage,
            isWorking: isWorking
        )
    }

    private func verify() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.verifyEmailCode(code, email: email, type: "signup")
            if let repository, let userID = auth.userID, let token = auth.accessToken {
                try? await repository.acceptTerms(version: "v1", userID: userID, token: token)
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
