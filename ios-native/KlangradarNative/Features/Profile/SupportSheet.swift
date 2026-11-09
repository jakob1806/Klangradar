// Erstellt von Claude Code (09.11.2026): „Problem melden“ – zweiter
// Kontaktweg neben der E-Mail (Impressum, App-Review), schreibt in
// support_messages (Migration 167).
import SwiftUI

struct SupportSheet: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var contact = ""
    @State private var state: SendState = .idle

    enum SendState: Equatable { case idle, sending, sent, failed }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Was ist passiert?", text: $message, axis: .vertical)
                        .lineLimit(5...12)
                } footer: {
                    Text("Fehler, Fragen, Hinweise auf Rechtsverletzungen oder unangemessene Inhalte. Wir antworten in der Regel innerhalb von 48 Stunden.")
                }
                Section {
                    TextField("E-Mail für die Antwort (optional)", text: $contact)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Link("Stattdessen E-Mail schreiben", destination: URL(string: "mailto:jakob@klangradar.com")!)
                }
                if state == .sent {
                    Label("Danke! Deine Nachricht ist angekommen.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if state == .failed {
                    Label("Senden fehlgeschlagen – bitte per E-Mail an jakob@klangradar.com.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .navigationTitle("Problem melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") { Task { await send() } }
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || state == .sending || state == .sent)
                }
            }
        }
    }

    private func send() async {
        guard let client = repository?.client, let token = auth.accessToken, let userID = auth.userID else { state = .failed; return }
        state = .sending
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        var values: JSONObject = ["user_id": .string(userID.uuidString), "message": .string(message.trimmingCharacters(in: .whitespacesAndNewlines)),
                                  "app_version": .string(version)]
        let trimmed = contact.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { values["contact"] = .string(trimmed) }
        do {
            _ = try await client.insert(table: "support_messages", values: values, accessToken: token)
            state = .sent
            Haptics.confirm()
        } catch {
            state = .failed
        }
    }
}
