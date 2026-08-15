import SwiftUI

/// Mockup-only: Formulardaten einer Veranstalter-/Ensemble-Bewerbung.
/// Es gibt (noch) kein Backend/Repository dafür — Absenden ist rein lokal simuliert.
struct PartnerApplicationRequest: Identifiable {
    let id = UUID()
    var organizationName = ""
    var role: PartnerApplicationRole = .venue
    var contactName = ""
    var email = ""
    var phone = ""
    var website = ""
    var city = ""
    var genres: Set<String> = []
    var message = ""

    var isValid: Bool {
        !organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.contains("@")
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum PartnerApplicationRole: String, CaseIterable, Identifiable {
    case venue = "Spielstätte"
    case organizer = "Veranstalter"
    case ensemble = "Ensemble"
    case soloist = "Solist:in"
    case other = "Sonstiges"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .venue: "building.columns"
        case .organizer: "calendar.badge.plus"
        case .ensemble: "person.3"
        case .soloist: "music.mic"
        case .other: "ellipsis.circle"
        }
    }
}

private let genreSuggestions = [
    "Klassik", "Kammermusik", "Chormusik", "Oper", "Zeitgenössisch",
    "Barock", "Jazz", "Alte Musik", "Orchester", "Soloabend"
]

/// Bewerbungs-Mockup: „Als Partner bei Klangradar bewerben“.
/// UI-only — es wird nichts an ein Backend gesendet, das Absenden wird lokal simuliert.
struct PartnerApplicationView: View {
    @State private var request = PartnerApplicationRequest()
    @State private var isSubmitting = false
    @State private var didSubmit = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bei Klangradar sichtbar werden", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(KlangradarTheme.accent)
                    Text("Spielstätten, Veranstalter und Ensembles können sich hier für eine Aufnahme in Klangradar bewerben. Unsere Redaktion meldet sich anschließend mit den nächsten Schritten.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Wer bewirbt sich?") {
                Picker("Rolle", selection: $request.role) {
                    ForEach(PartnerApplicationRole.allCases) { role in
                        Label(role.rawValue, systemImage: role.systemImage).tag(role)
                    }
                }
                TextField("Name der Organisation / des Ensembles", text: $request.organizationName)
                    .textContentType(.organizationName)
                TextField("Stadt", text: $request.city)
                    .textContentType(.addressCity)
            }

            Section("Kontakt") {
                TextField("Ansprechpartner:in", text: $request.contactName)
                    .textContentType(.name)
                TextField("E-Mail-Adresse", text: $request.email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                TextField("Telefon (optional)", text: $request.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Webseite (optional)", text: $request.website)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            Section {
                GenreChipFlow(selection: $request.genres)
            } header: {
                Text("Passende Genres")
            } footer: {
                Text("Hilft der Redaktion bei der ersten Einordnung. Änderbar bis zur Freischaltung.")
            }

            Section("Kurzbeschreibung") {
                TextEditor(text: $request.message)
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if request.message.isEmpty {
                            Text("Was zeichnet euer Programm aus?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Bewerbung senden")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .listRowBackground(KlangradarTheme.accent)
                .foregroundStyle(.white)
                .disabled(!request.isValid || isSubmitting)
            } footer: {
                Text("Mockup: Diese Bewerbung wird noch nicht an ein Backend übertragen.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Als Partner bewerben")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Bewerbung gesendet", isPresented: $didSubmit) {
            Button("Fertig", role: .cancel) { request = PartnerApplicationRequest() }
        } message: {
            Text("Danke! Die Klangradar-Redaktion meldet sich in Kürze bei \(request.email.isEmpty ? "dir" : request.email).")
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            isSubmitting = false
            didSubmit = true
        }
    }
}

private struct GenreChipFlow: View {
    @Binding var selection: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(genreSuggestions, id: \.self) { genre in
                let isSelected = selection.contains(genre)
                Button {
                    if isSelected { selection.remove(genre) } else { selection.insert(genre) }
                } label: {
                    Text(genre)
                        .font(.subheadline)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? KlangradarTheme.accent : Color.secondary.opacity(0.12),
                            in: .capsule
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        PartnerApplicationView()
    }
}
