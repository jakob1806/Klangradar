import SwiftUI

/// "Passwort vergessen"-Flow: E-Mail → Code aus der Recovery-Mail → neues
/// Passwort. Nutzt denselben `verify`-Endpoint wie die Signup-Bestätigung,
/// nur mit `type: "recovery"` (siehe AuthService.verifyEmailCode).
struct ForgotPasswordView: View {
    @ObservedObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    private enum Step { case requestEmail, enterCode, setPassword, done }

    @State private var step: Step = .requestEmail
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var newPasswordConfirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                stepFields

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(primaryButtonTitle) { Task { await primaryAction() } }
                        .disabled(isWorking || !canProceed)
                }
            }
            .navigationTitle("Passwort vergessen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .done ? "Fertig" : "Abbrechen") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    @ViewBuilder
    private var stepFields: some View {
        switch step {
        case .requestEmail:
            Section {
                TextField("E-Mail-Adresse", text: $email)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            } footer: {
                Text("Wir schicken dir einen Code, mit dem du ein neues Passwort festlegen kannst.")
            }
        case .enterCode:
            Section {
                TextField("Code aus der E-Mail", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
            }
        case .setPassword:
            Section {
                SecureField("Neues Passwort (mind. 8 Zeichen)", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Passwort wiederholen", text: $newPasswordConfirmation)
                    .textContentType(.newPassword)
            }
        case .done:
            Section {
                Label("Dein Passwort wurde geändert.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var canProceed: Bool {
        switch step {
        case .requestEmail: !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .enterCode: !code.isEmpty
        case .setPassword: newPassword.count >= 8 && newPassword == newPasswordConfirmation
        case .done: false
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .requestEmail: "Code senden"
        case .enterCode: "Code bestätigen"
        case .setPassword: "Passwort speichern"
        case .done: "Fertig"
        }
    }

    private func primaryAction() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            switch step {
            case .requestEmail:
                try await auth.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                step = .enterCode
            case .enterCode:
                try await auth.verifyEmailCode(
                    code,
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    type: "recovery"
                )
                step = .setPassword
            case .setPassword:
                try await auth.updatePassword(newPassword)
                step = .done
            case .done:
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
