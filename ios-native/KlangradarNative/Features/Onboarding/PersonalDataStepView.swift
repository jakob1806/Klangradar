import SwiftUI

/// Bewusst kurzer Profilschritt: Nur der Vorname ist erforderlich. Nachname
/// und Geburtsdatum sind freiwillig; Profilbild, Telefon und Adresse bleiben
/// im späteren Profil und blockieren die Registrierung nicht.
struct PersonalDataStepView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onSaved: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var hasBirthDate = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Vorname", text: $firstName).textContentType(.givenName)
                TextField("Nachname (optional)", text: $lastName).textContentType(.familyName)
                Toggle("Geburtsdatum angeben", isOn: $hasBirthDate.animation())
                if hasBirthDate {
                    DatePicker("Geburtsdatum", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                }
            } header: {
                Text("Über dich")
            } footer: {
                Text("Nachname und Geburtsdatum sind freiwillig. Profilbild, Telefonnummer und Adresse kannst du später im Profil ergänzen.")
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Über dich")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await save() } } label: { Text("Weiter").frame(maxWidth: .infinity) }
                .authPrimaryButtonStyle()
                .controlSize(.large)
                .disabled(!isValid || isWorking)
                .authBottomActionLayout()
        }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .interactiveDismissDisabled(isWorking)
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            onSaved()
            return
        }
        let cleanFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanLast.isEmpty ? cleanFirst : "\(cleanFirst) \(cleanLast)"
        do {
            try await repository.updatePersonalData(firstName: cleanFirst, lastName: cleanLast, userID: userID, token: token)
            if hasBirthDate {
                try await repository.updateProfile(displayName: displayName, birthDate: birthDate, userID: userID, token: token)
            }
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
