import SwiftUI

/// Fordert den sicheren Supabase-Recovery-Link an. Der Link öffnet über das
/// registrierte URL-Schema wieder die App; RootTabView zeigt anschließend
/// `PasswordResetCompletionView` an.
struct ForgotPasswordView: View {
    @ObservedObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    private enum Step { case requestEmail, sent }

    @State private var step: Step = .requestEmail
    @State private var email = ""
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

                if step == .requestEmail {
                    EmptyView()
                }
            }
            .navigationTitle("Passwort vergessen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Schließen", systemImage: "xmark")
                    }
                }
            }
            .interactiveDismissDisabled(isWorking)
            .safeAreaInset(edge: .bottom) {
                if step == .requestEmail {
                    Button { Task { await requestLink() } } label: {
                        Text("Reset-Link senden").frame(maxWidth: .infinity)
                    }
                        .authPrimaryButtonStyle()
                        .controlSize(.large)
                        .disabled(isWorking || !isEmailValid)
                        .authBottomActionLayout()
                }
            }
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .onChange(of: auth.isCompletingPasswordRecovery) { _, isRecovering in
                if isRecovering { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var stepFields: some View {
        switch step {
        case .requestEmail:
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 40))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(KlangradarTheme.accent)
                    Text("Gib die E-Mail-Adresse deines Accounts ein.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                TextField("E-Mail-Adresse", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
            } footer: {
                Text("Wir schicken dir einen sicheren Link. Öffne ihn auf diesem Gerät, um ein neues Passwort festzulegen.")
            }
        case .sent:
            Section {
                ContentUnavailableView {
                    Label("E-Mail wurde versendet", systemImage: "envelope.badge.fill")
                } description: {
                    Text("Öffne den Link aus der E-Mail auf diesem Gerät. Prüfe auch deinen Spam-Ordner.")
                } actions: {
                    Button("Fertig") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var isEmailValid: Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanEmail.contains("@") && cleanEmail.contains(".")
    }

    private func requestLink() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            step = .sent
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PasswordResetCompletionView: View {
    @ObservedObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showsPassword = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var requirements: [(title: String, isMet: Bool)] { AuthPasswordPolicy.requirements(for: password) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Neues Passwort") {
                    RevealablePasswordField(title: "Passwort", text: $password, isRevealed: $showsPassword, textContentType: .newPassword)
                    RevealablePasswordField(title: "Passwort wiederholen", text: $confirmation, isRevealed: $showsPassword, textContentType: .newPassword)
                }
                Section {
                    ForEach(requirements, id: \.title) { item in
                        Label(item.title, systemImage: item.isMet ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isMet ? .green : .secondary)
                    }
                    if !confirmation.isEmpty, password != confirmation {
                        Label("Die Passwörter stimmen nicht überein.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Passwort festlegen")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { Task { await save() } } label: {
                    Text("Passwort speichern").frame(maxWidth: .infinity)
                }
                    .authPrimaryButtonStyle()
                    .controlSize(.large)
                    .disabled(isWorking || !AuthPasswordPolicy.isValid(password) || password != confirmation)
                    .authBottomActionLayout()
            }
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .interactiveDismissDisabled()
        }
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.updatePassword(password)
            auth.isCompletingPasswordRecovery = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
