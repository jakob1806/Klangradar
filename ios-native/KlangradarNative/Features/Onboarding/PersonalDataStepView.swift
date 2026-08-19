import SwiftUI

/// Schritt "Persönliche Daten". Vor-/Nachname verpflichtend, alles andere
/// optional — Profilbild nutzt den bestehenden ProfileAvatarEditor
/// unverändert (der ist bereits an `auth`/`repository` gebunden und
/// funktioniert unabhängig davon, ob er im Profil-Tab oder hier im
/// Onboarding angezeigt wird).
struct PersonalDataStepView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onSaved: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var phone = ""
    @State private var address = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Persönliche Daten")
                    .font(.largeTitle.bold())
                Text("Damit dein Profil zu dir passt.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            ProfileAvatarEditor(auth: auth, repository: repository)

            Form {
                Section {
                    TextField("Vorname", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Nachname", text: $lastName)
                        .textContentType(.familyName)
                }
                Section {
                    Toggle("Geburtstag hinterlegen", isOn: $hasBirthDate.animation())
                    if hasBirthDate {
                        DatePicker("Geburtstag", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                    }
                }
                Section {
                    TextField("Telefonnummer (optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Adresse / Wohnort (optional)", text: $address)
                        .textContentType(.fullStreetAddress)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)

            Button("Weiter") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!isValid || isWorking)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            onSaved()
            return
        }
        do {
            try await repository.updatePersonalData(
                firstName: firstName,
                lastName: lastName,
                phone: phone.isEmpty ? nil : phone,
                address: address.isEmpty ? nil : address,
                userID: userID,
                token: token
            )
            if hasBirthDate {
                try await repository.updateProfile(displayName: "\(firstName) \(lastName)", birthDate: birthDate, userID: userID, token: token)
            }
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
