import SwiftUI

/// KI-gestützte Recherche/Vervollständigung — eingebettet sowohl im
/// Entity-Editor als auch im Event-Editor, daher hier statt in einer der
/// beiden Dateien.
struct EditorialAIAssistantView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let entityType: String
    let entityID: UUID

    @State private var prompt = ""
    @State private var answer: String?
    @State private var proposals: [EditorialAIProposal] = []
    @State private var selected: Set<UUID> = []
    @State private var drafts: [UUID: String] = [:]
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        EditorialCard(title: "Gemini Recherche", icon: "sparkles") {
            Text("Recherchiert mit Quellen. Änderungen werden erst nach deiner Auswahl zentral übernommen.")
                .font(.caption).foregroundStyle(.secondary)
            if let answer {
                Text(answer).font(.subheadline).textSelection(.enabled)
            }
            ForEach(proposals) { proposal in
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(isOn: Binding(
                        get: { selected.contains(proposal.id) },
                        set: { enabled in if enabled { selected.insert(proposal.id) } else { selected.remove(proposal.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.label(proposal.field)).font(.subheadline.bold())
                        }
                    }
                    .disabled(proposal.confidence == "unclear")
                    TextField("Wert vor Übernahme bearbeiten", text: Binding(
                        get: { drafts[proposal.id] ?? Self.display(proposal.value) },
                        set: { drafts[proposal.id] = $0 }
                    ), axis: .vertical)
                    .lineLimit(proposal.field == "biography_de" || proposal.field == "description_de" ? 5...12 : 1...4)
                    .disabled(proposal.confidence == "unclear")
                    if let rationale = proposal.rationale { Text(rationale).font(.caption2).foregroundStyle(.secondary) }
                    if !proposal.sourceURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(proposal.sourceURLs, id: \.self) { source in
                                if let url = URL(string: source) { Link("Quelle", destination: url).font(.caption2).foregroundStyle(KlangradarTheme.accent) }
                            } }
                        }
                    }
                }
                .padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            if !selected.isEmpty {
                Button("\(selected.count) Felder übernehmen", systemImage: "checkmark.icloud") { Task { await apply() } }
                    .buttonStyle(.borderedProminent).tint(.green).disabled(isWorking)
            }
            TextField("Was soll Gemini recherchieren?", text: $prompt, axis: .vertical)
                .lineLimit(2...5)
            Button("Recherchieren", systemImage: "sparkle.magnifyingglass") { Task { await ask() } }
                .buttonStyle(EditorialPrimaryButtonStyle()).disabled(isWorking || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if isWorking { ProgressView().tint(KlangradarTheme.accent) }
            if let message { Text(message).font(.caption).foregroundStyle(message.contains("übernommen") ? .green : .red) }
        }
    }

    @MainActor private func ask() async {
        guard let token = auth.accessToken else { return }
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isWorking = true; message = nil; defer { isWorking = false }
        do {
            let reply = try await repository.askEditorialAI(entityType: entityType, entityID: entityID, message: question, token: token)
            answer = reply.answer; proposals = reply.proposals; selected = []; drafts = [:]; prompt = ""
        } catch { message = error.localizedDescription }
    }

    @MainActor private func apply() async {
        guard let token = auth.accessToken else { return }
        isWorking = true; message = nil; defer { isWorking = false }
        do {
            let edited = try proposals.filter { selected.contains($0.id) }.map { proposal in
                EditorialAIProposal(field: proposal.field, value: try Self.parse(drafts[proposal.id] ?? Self.display(proposal.value), like: proposal.value), confidence: proposal.confidence, rationale: proposal.rationale, sourceURLs: proposal.sourceURLs)
            }
            try await repository.applyEditorialAI(entityType: entityType, entityID: entityID, proposals: edited, token: token)
            message = "Ausgewählte Angaben zentral übernommen."; selected = []; drafts = [:]
        } catch { message = error.localizedDescription }
    }

    private static func display(_ value: JSONValue) -> String {
        switch value {
        case let .string(value): value
        case let .number(value): value.rounded() == value ? String(Int(value)) : String(value)
        case let .bool(value): value ? "Ja" : "Nein"
        case let .array(values): values.map(display).joined(separator: ", ")
        case let .object(value): value.map { "\($0.key): \(display($0.value))" }.sorted().joined(separator: ", ")
        case .null: "Leer"
        }
    }

    private static func parse(_ draft: String, like original: JSONValue) throws -> JSONValue {
        switch original {
        case .string: return .string(draft.trimmingCharacters(in: .whitespacesAndNewlines))
        case .number:
            guard let value = Double(draft.replacingOccurrences(of: ",", with: ".")) else { throw EditorialError.validation("„\(draft)“ ist keine gültige Zahl.") }
            return .number(value)
        case .bool: return .bool(["ja", "true", "1"].contains(draft.lowercased().trimmingCharacters(in: .whitespaces)))
        case .array:
            return .array(draft.components(separatedBy: CharacterSet(charactersIn: "\n,")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map(JSONValue.string))
        case .object, .null: return original
        }
    }

    private static func label(_ field: String) -> String {
        ["biography_de": "Biografie", "birth_date": "Geburtsdatum", "death_date": "Sterbedatum", "nationality": "Nationalität",
         "instrument": "Instrument", "roles": "Rollen", "description_de": "Beschreibung", "founded_year": "Gründungsjahr",
         "member_count": "Mitgliederzahl", "title": "Titel", "catalog_number": "Werkverzeichnis", "composition_year": "Entstehungsjahr",
         "duration_minutes": "Dauer", "program_notes_de": "Programmtext", "instrumentation": "Besetzung", "movements": "Sätze"][field] ?? field
    }
}
