import SwiftUI

/// Schritt 2 "Account erstellen": E-Mail + Passwort, Anforderungen live
/// angezeigt (muss zur Supabase-Passwort-Policy passen, siehe
/// backend/supabase/config.toml minimum_password_length/
/// password_requirements), AGB/Datenschutz-Zustimmung. Verschickt bei Erfolg
/// automatisch die Bestätigungs-Mail (Supabase, `enable_confirmations`) —
/// der eigentliche Haken wird erst nach `acceptTerms` im nächsten Schritt
/// gesetzt, sobald eine echte (nicht mehr anonyme) Session existiert.
struct SignUpStepView: View {
    @ObservedObject var auth: AuthStore
    let onSignedUp: (String) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var acceptedTerms = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsImpressum = false

    private var requirements: [(String, Bool)] {
        [
            ("Mindestens 8 Zeichen", password.count >= 8),
            ("Groß- und Kleinbuchstaben", password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase)),
            ("Mindestens eine Zahl", password.contains(where: \.isNumber))
        ]
    }

    private var isValid: Bool {
        email.contains("@")
            && requirements.allSatisfy(\.1)
            && password == passwordConfirmation
            && acceptedTerms
    }

    var body: some View {
        OnboardingStepScaffold(
            title: "Account erstellen",
            subtitle: "Mit E-Mail und Passwort — ein Passwort brauchst du nur einmal festzulegen.",
            content: {
                VStack(spacing: 14) {
                    TextField("E-Mail-Adresse", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Passwort", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                    SecureField("Passwort wiederholen", text: $passwordConfirmation)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(requirements, id: \.0) { requirement in
                            Label(requirement.0, systemImage: requirement.1 ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(requirement.1 ? .green : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle("Ich akzeptiere die AGB und die Datenschutzerklärung", isOn: $acceptedTerms)
                        .font(.footnote)
                        .toggleStyle(.switch)
                    HStack(spacing: 16) {
                        Button("Impressum (AGB)") { showsImpressum = true }
                        Link("Datenschutz", destination: URL(string: "https://klangradar.app/datenschutz")!)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            },
            primaryTitle: "Weiter",
            isPrimaryEnabled: isValid,
            onPrimary: { Task { await signUp() } },
            errorMessage: errorMessage,
            isWorking: isWorking
        )
        .sheet(isPresented: $showsImpressum) {
            NavigationStack {
                ImpressumView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fertig") { showsImpressum = false }
                        }
                    }
            }
        }
    }

    private func signUp() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            try await auth.signUp(email: cleanEmail, password: password)
            onSignedUp(cleanEmail)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
