import SwiftUI

private enum EditorialProgramCandidateKind: String, CaseIterable, Identifiable {
    case work, person, ensemble, ignore
    var id: String { rawValue }
    var title: String {
        switch self {
        case .work: "Werk"
        case .person: "Person (Komponist:in/Mitwirkende:r)"
        case .ensemble: "Ensemble"
        case .ignore: "Ignorieren"
        }
    }
    var symbol: String {
        switch self {
        case .work: "music.note"
        case .person: "person"
        case .ensemble: "person.3"
        case .ignore: "eye.slash"
        }
    }
}

private struct EditorialProgramCandidate: Identifiable {
    let id = UUID()
    var rawText: String
    var kind: EditorialProgramCandidateKind
    var role: String = ""
    var matchedOptionID: UUID?
    var createNew: Bool = false
}

private enum EditorialProgramScanStage {
    case scanning
    case recognizing
    case review
    case takingOver
    case done(added: Int)
}

/// Punkt 18, "Programmheft-Scan/OCR": Kamera → Texterkennung → Zeilen als
/// Werk/Person/Ensemble klassifizieren (mit automatisch vorgeschlagenem
/// Datenbank-Treffer) → Review → Übernahme ins Programm/die Mitwirkenden
/// des Ziel-Events, über dieselben Repository-Aufrufe wie der reguläre
/// Event-Editor (addWork/addParticipant/createEntity).
struct EditorialProgramScanView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let event: EditorialEvent
    let existingWorkCount: Int
    let onCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stage: EditorialProgramScanStage = .scanning
    @State private var candidates: [EditorialProgramCandidate] = []
    @State private var persons: [EditorialOption] = []
    @State private var ensembles: [EditorialOption] = []
    @State private var works: [EditorialOption] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                EditorialBackground()
                switch stage {
                case .scanning:
                    EditorialDocumentScanner(
                        onScanned: { images in Task { await recognize(images) } },
                        onCancelled: { dismiss() }
                    )
                    .ignoresSafeArea()
                case .recognizing:
                    ProgressView("Text wird erkannt …").tint(KlangradarTheme.accent)
                case .review:
                    reviewList
                case .takingOver:
                    ProgressView("Programm wird übernommen …").tint(KlangradarTheme.accent)
                case let .done(added):
                    ContentUnavailableView {
                        Label("Übernommen", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text("\(added) Einträge zum Programm hinzugefügt.")
                    }
                }
            }
            .navigationTitle("Programmheft scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { onCompleted(); dismiss() } }
            }
            .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var reviewList: some View {
        List {
            Section {
                Text("\(candidates.count) Zeilen erkannt. Bitte jede Zeile zuordnen — falsch erkannte oder unwichtige Zeilen einfach auf „Ignorieren“ stellen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($candidates) { $candidate in
                EditorialProgramCandidateRow(
                    candidate: $candidate,
                    options: options(for: candidate.kind)
                )
            }
            Section {
                Button {
                    Task { await takeOver() }
                } label: {
                    Label("Programm übernehmen", systemImage: "checkmark.icloud")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
                .disabled(candidates.allSatisfy { $0.kind == .ignore })
            }
        }
        .listStyle(.insetGrouped)
    }

    private func options(for kind: EditorialProgramCandidateKind) -> [EditorialOption] {
        switch kind {
        case .work: works
        case .person: persons
        case .ensemble: ensembles
        case .ignore: []
        }
    }

    @MainActor private func recognize(_ images: [UIImage]) async {
        stage = .recognizing
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; stage = .review; return }
        async let loadedPersons = (try? await repository.persons(token: token)) ?? []
        async let loadedEnsembles = (try? await repository.ensembles(token: token)) ?? []
        async let loadedWorks = (try? await repository.works(token: token)) ?? []
        let lines = await EditorialProgramOCR.recognizeLines(in: images)
        persons = await loadedPersons
        ensembles = await loadedEnsembles
        works = await loadedWorks

        candidates = lines.map { line in
            // Grobe Heuristik zur Vorklassifizierung — Zahlen/op./KV/BWV
            // deuten stark auf einen Werktitel hin, sonst Best-Match gegen
            // Personen zuerst (häufigster Fall: Komponist:in oder
            // Mitwirkende:r), dann Ensembles.
            let looksLikeWork = line.range(of: #"\d"#, options: .regularExpression) != nil
                || line.lowercased().contains("op.") || line.lowercased().contains("kv")

            if looksLikeWork, let match = EditorialProgramOCR.bestMatch(for: line, in: works) {
                return EditorialProgramCandidate(rawText: line, kind: .work, matchedOptionID: match.id)
            }
            if let match = EditorialProgramOCR.bestMatch(for: line, in: persons) {
                return EditorialProgramCandidate(rawText: line, kind: .person, matchedOptionID: match.id)
            }
            if let match = EditorialProgramOCR.bestMatch(for: line, in: ensembles) {
                return EditorialProgramCandidate(rawText: line, kind: .ensemble, matchedOptionID: match.id)
            }
            return EditorialProgramCandidate(rawText: line, kind: looksLikeWork ? .work : .person, createNew: true)
        }
        stage = .review
    }

    @MainActor private func takeOver() async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        stage = .takingOver
        var added = 0
        var nextPosition = existingWorkCount
        for candidate in candidates where candidate.kind != .ignore {
            do {
                let entityKind: EditorialEntityKind = candidate.kind == .work ? .work : candidate.kind == .ensemble ? .ensemble : .person
                let option: EditorialOption
                if let matchedID = candidate.matchedOptionID, let match = options(for: candidate.kind).first(where: { $0.id == matchedID }) {
                    option = match
                } else {
                    let created = try await repository.createEntity(
                        kind: entityKind, title: candidate.rawText, subtitle: "", description: "",
                        imageURL: "", composerID: nil, actor: actor, token: token
                    )
                    option = EditorialOption(id: created.id, title: created.title, subtitle: created.subtitle)
                }
                switch candidate.kind {
                case .work:
                    try await repository.addWork(eventID: event.id, option: option, position: nextPosition, actor: actor, token: token)
                    nextPosition += 1
                case .person:
                    try await repository.addParticipant(eventID: event.id, option: option, type: "person", role: candidate.role, actor: actor, token: token)
                case .ensemble:
                    try await repository.addParticipant(eventID: event.id, option: option, type: "ensemble", role: candidate.role, actor: actor, token: token)
                case .ignore:
                    continue
                }
                added += 1
            } catch {
                errorMessage = "„\(candidate.rawText)“ konnte nicht übernommen werden: \(error.localizedDescription)"
            }
        }
        stage = .done(added: added)
    }
}

private struct EditorialProgramCandidateRow: View {
    @Binding var candidate: EditorialProgramCandidate
    let options: [EditorialOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate.rawText).font(.subheadline.weight(.medium)).lineLimit(2)

            Picker("Art", selection: $candidate.kind) {
                ForEach(EditorialProgramCandidateKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.menu).tint(KlangradarTheme.accent)

            if candidate.kind != .ignore {
                if candidate.kind != .work {
                    TextField("Rolle, z. B. Dirigent:in, Sopran", text: $candidate.role)
                        .font(.caption)
                }
                if let matchID = candidate.matchedOptionID, let match = options.first(where: { $0.id == matchID }) {
                    Label("Zugeordnet: \(match.title)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Button("Stattdessen neu anlegen") { candidate.matchedOptionID = nil; candidate.createNew = true }
                        .font(.caption2)
                } else {
                    Label("Wird neu angelegt als „\(candidate.rawText)“", systemImage: "plus.circle")
                        .font(.caption).foregroundStyle(.orange)
                    if !options.isEmpty {
                        Menu("Stattdessen vorhandenen Eintrag wählen") {
                            ForEach(options.prefix(30)) { option in
                                Button(option.title) { candidate.matchedOptionID = option.id; candidate.createNew = false }
                            }
                        }
                        .font(.caption2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
