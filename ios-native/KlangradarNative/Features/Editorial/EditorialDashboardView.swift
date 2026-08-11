import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct EditorialDashboardView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository

    @State private var events: [EditorialEvent] = []
    @State private var entities: [EditorialEntity] = []
    @State private var searchText = ""
    @State private var scope: EditorialScope = .events
    @State private var createKind: EditorialEntityKind?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            EditorialBackground()
            VStack(spacing: 0) {
                Picker("Bereich", selection: $scope) {
                    ForEach(EditorialScope.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(KlangradarTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Group {
                if isLoading { ProgressView("Redaktionsdaten werden geladen …").tint(.orange) }
                else if let errorMessage { ContentUnavailableView("Redaktion nicht verfügbar", systemImage: "exclamationmark.shield", description: Text(errorMessage)) }
                else { resultList }
                }
            }
        }
        .navigationTitle("Redaktion")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "\(scope.title) durchsuchen")
        .toolbar {
            if let kind = scope.creatableKind {
                ToolbarItem(placement: .primaryAction) {
                    Button("\(kind.singularTitle) hinzufügen", systemImage: "plus") { createKind = kind }
                }
            }
        }
        .sheet(item: $createKind) { kind in
            EditorialCreateEntityView(auth: auth, repository: repository, kind: kind) { _ in
                Task { await load() }
            }
        }
        .task(id: scope) { await load() }
    }

    private var resultList: some View {
        List {
            Section { EditorialModeBanner() }
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

            Section(scope.title) {
                if scope == .events {
                    ForEach(filteredEvents) { event in
                        NavigationLink {
                            EditorialEventEditorView(auth: auth, repository: repository, initialEvent: event)
                        } label: {
                            EditorialEventRow(event: event)
                        }
                    }
                } else {
                    ForEach(filteredEntities) { entity in
                        NavigationLink {
                            EditorialEntityEditorView(auth: auth, repository: repository, entity: entity)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entity.title)
                                    if let subtitle = entity.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                            } icon: {
                                EditorialThumbnail(url: entity.imageURL, symbol: entity.kind.symbol)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private var filteredEvents: [EditorialEvent] {
        guard !searchText.isEmpty else { return events }
        return events.filter { $0.title.localizedStandardContains(searchText) || ($0.subtitle?.localizedStandardContains(searchText) == true) || $0.venueName.localizedStandardContains(searchText) }
    }

    private var filteredEntities: [EditorialEntity] {
        guard !searchText.isEmpty else { return entities }
        return entities.filter { $0.title.localizedStandardContains(searchText) || ($0.subtitle?.localizedStandardContains(searchText) == true) }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; isLoading = false; return }
        isLoading = events.isEmpty
        defer { isLoading = false }
        do {
            if scope == .events {
                events = try await repository.events(search: "", token: token)
            } else if let kind = scope.entityKind {
                entities = try await repository.entities(kind: kind, token: token)
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private enum EditorialScope: String, CaseIterable, Identifiable {
    case events, venues, persons, ensembles, works
    var id: String { rawValue }
    var title: String { switch self { case .events: "Veranstaltungen"; case .venues: "Venues"; case .persons: "Personen"; case .ensembles: "Ensembles"; case .works: "Werke" } }
    var symbol: String { switch self { case .events: "calendar"; case .venues: "building.columns"; case .persons: "person"; case .ensembles: "person.3"; case .works: "music.note" } }
    var entityKind: EditorialEntityKind? { switch self { case .events: nil; case .venues: .venue; case .persons: .person; case .ensembles: .ensemble; case .works: .work } }
    var creatableKind: EditorialEntityKind? { switch self { case .persons: .person; case .ensembles: .ensemble; case .works: .work; default: nil } }
}

private struct EditorialCreateEntityView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let kind: EditorialEntityKind
    let onCreated: (EditorialEntity) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var subtitle = ""
    @State private var description = ""
    @State private var imageURL = ""
    @State private var pendingProfileImageData: Data?
    @State private var pendingImageData: [Data] = []
    @State private var composerID: UUID?
    @State private var composerName: String?
    @State private var persons: [EditorialOption] = []
    @State private var showsComposerPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(titleLabel, text: $title)
                    if kind == .person { TextField("Instrument", text: $subtitle) }
                    if kind == .work {
                        TextField("Werkverzeichnis", text: $subtitle)
                        Button { showsComposerPicker = true } label: {
                            LabeledContent("Komponist:in", value: composerName ?? "Auswählen")
                        }.foregroundStyle(.primary)
                    }
                    TextField(kind == .person ? "Biografie" : "Beschreibung", text: $description, axis: .vertical)
                        .lineLimit(4...10)
                } header: { Text("Neuer Eintrag") }

                Section("Bilder") {
                    if kind != .work {
                        TextField(kind == .person || kind == .ensemble ? "Profilfoto-URL (optional)" : "Bild-URL (optional)", text: $imageURL)
                            .textInputAutocapitalization(.never).keyboardType(.URL)
                        if kind == .person || kind == .ensemble {
                            EditorialImagePickerButtons(
                                onImages: { pendingProfileImageData = $0.first },
                                onError: { errorMessage = $0 },
                                allowsMultipleSelection: false
                            )
                            if pendingProfileImageData != nil {
                                Label("Profilfoto ausgewählt", systemImage: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(.green)
                            }
                            Divider()
                        }
                    }
                    Text("Bildergalerie").font(.subheadline.weight(.semibold))
                    EditorialImagePickerButtons { data in
                        pendingImageData.append(contentsOf: data)
                    } onError: { errorMessage = $0 }
                    if !pendingImageData.isEmpty {
                        Label("\(pendingImageData.count) Bild(er) ausgewählt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button { Task { await create() } } label: {
                        Label("\(kind.singularTitle) anlegen", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                } footer: {
                    Text("Der neue Eintrag wird sofort zentral gespeichert und kann anschließend Veranstaltungen zugeordnet werden.")
                }
            }
            .navigationTitle("\(kind.singularTitle) hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .overlay { if isSaving { ProgressView() } }
            .sheet(isPresented: $showsComposerPicker) {
                EditorialSimpleOptionPicker(title: "Komponist:in", options: persons) { option in
                    composerID = option.id; composerName = option.title
                }
            }
            .alert("Eintrag nicht angelegt", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .task {
                guard kind == .work, let token = auth.accessToken else { return }
                persons = (try? await repository.persons(token: token)) ?? []
            }
        }
    }

    private var titleLabel: String { kind == .person ? "Vollständiger Name" : kind == .ensemble ? "Ensemble-Name" : "Werktitel" }

    @MainActor private func create() async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let entity = try await repository.createEntity(kind: kind, title: title, subtitle: subtitle, description: description, imageURL: imageURL, composerID: composerID, actor: actor, token: token)
            var createdEntity = entity
            if let pendingProfileImageData, (kind == .person || kind == .ensemble) {
                let profileURL = try await repository.uploadEditorialImage(data: pendingProfileImageData, originType: "\(kind.rawValue)-profiles", originID: entity.id, token: token)
                try await repository.updateEntity(entity: entity, title: title, subtitle: subtitle, description: description, imageURL: profileURL.absoluteString, composerID: composerID, actor: actor, token: token)
                createdEntity = EditorialEntity(id: entity.id, kind: kind, title: entity.title, subtitle: entity.subtitle, editableSubtitle: entity.editableSubtitle, description: entity.description, imageURL: profileURL.absoluteString, composerID: entity.composerID)
            }
            if !pendingImageData.isEmpty {
                _ = try await repository.addGalleryImages(data: pendingImageData, originType: kind.rawValue, originID: entity.id, actor: actor, token: token)
            }
            onCreated(createdEntity)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct EditorialEntityEditorView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let entity: EditorialEntity
    let onSaved: () -> Void

    @State private var title: String
    @State private var subtitle: String
    @State private var description: String
    @State private var imageURL: String
    @State private var composerID: UUID?
    @State private var composerName: String?
    @State private var persons: [EditorialOption] = []
    @State private var showsComposerPicker = false
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?

    init(auth: AuthStore, repository: EditorialRepository, entity: EditorialEntity, onSaved: @escaping () -> Void = {}) {
        self.auth = auth; self.repository = repository; self.entity = entity
        self.onSaved = onSaved
        _title = State(initialValue: entity.title)
        _subtitle = State(initialValue: entity.editableSubtitle ?? "")
        _description = State(initialValue: entity.description ?? "")
        _imageURL = State(initialValue: entity.imageURL ?? "")
        _composerID = State(initialValue: entity.composerID)
    }

    var body: some View {
        Form {
            Section {
                EditorialModeBanner(compact: true)
            }
            masterDataSection
            imagesSection
            saveSection
        }
        .navigationTitle(entity.kind.singularTitle + " bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .overlay { if isSaving { ProgressView() } }
        .sheet(isPresented: $showsComposerPicker) {
            EditorialSimpleOptionPicker(title: "Komponist:in", options: persons) { option in
                composerID = option.id; composerName = option.title
            }
        }
        .alert("Änderung nicht gespeichert", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task {
            guard entity.kind == .work, let token = auth.accessToken else { return }
            persons = (try? await repository.persons(token: token)) ?? []
            composerName = persons.first { $0.id == composerID }?.title
        }
    }

    private var titleLabel: String { entity.kind == .work ? "Werktitel" : entity.kind == .person ? "Name" : entity.kind == .venue ? "Venue-Name" : "Ensemble-Name" }
    private var descriptionLabel: String { entity.kind == .person ? "Biografie" : "Beschreibung" }

    private var masterDataSection: some View {
        Section("Stammdaten") {
            TextField(titleLabel, text: $title)
            if entity.kind == .person { TextField("Instrument", text: $subtitle) }
            if entity.kind == .work {
                TextField("Werkverzeichnis", text: $subtitle)
                Button { showsComposerPicker = true } label: {
                    LabeledContent("Komponist:in", value: composerName ?? "Auswählen")
                }.foregroundStyle(.primary)
            }
            TextField(descriptionLabel, text: $description, axis: .vertical)
                .lineLimit(4...12)
        }
    }

    private var imagesSection: some View {
        Section("Bildergalerie") {
            if entity.kind != .work {
                TextField(profileImageLabel, text: $imageURL, axis: .vertical)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                if entity.kind == .person || entity.kind == .ensemble { profileImageEditor }
            }
            EditorialGalleryEditor(auth: auth, repository: repository, originType: entity.kind.rawValue, originID: entity.id) { primaryURL in
                if entity.kind == .venue { imageURL = primaryURL ?? "" }
            }
        }
    }

    private var profileImageLabel: String {
        entity.kind == .person || entity.kind == .ensemble ? "Profilfoto-URL" : "Titelbild-URL"
    }

    private var profileImageEditor: some View {
        Group {
            EditorialImagePickerButtons(
                onImages: { selected in
                    guard let profileImage = selected.first else { return }
                    Task { await uploadProfileImage(profileImage) }
                },
                onError: { errorMessage = $0 },
                allowsMultipleSelection: false
            )
            if let url = URL(string: imageURL), !imageURL.isEmpty {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() }
                    .frame(width: 112, height: 112).clipShape(Circle()).clipped()
            }
            Text("Dieses Profilfoto wird für alle kleinen und großen Miniaturansichten verwendet.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var saveSection: some View {
        Section {
            Button { Task { await save() } } label: {
                Label(saved ? "Gespeichert" : "Zentral speichern", systemImage: saved ? "checkmark.circle.fill" : "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
        } footer: {
            Text("Die Änderung ist anschließend in allen Klangradar-Anwendungen verfügbar und wird protokolliert.")
        }
    }

    @MainActor private func save(imageOverride: String? = nil) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isSaving = true; saved = false; defer { isSaving = false }
        do {
            try await repository.updateEntity(entity: entity, title: title, subtitle: subtitle, description: description, imageURL: imageOverride ?? imageURL, composerID: composerID, actor: actor, token: token)
            if let imageOverride { imageURL = imageOverride }
            saved = true
            onSaved()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func removeImage() async { await save(imageOverride: "") }

    @MainActor private func uploadProfileImage(_ data: Data) async {
        guard let token = auth.accessToken else { return }
        isSaving = true; saved = false
        do {
            let url = try await repository.uploadEditorialImage(data: data, originType: "\(entity.kind.rawValue)-profiles", originID: entity.id, token: token)
            isSaving = false
            await save(imageOverride: url.absoluteString)
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

}

private struct EditorialSimpleOptionPicker: View {
    let title: String
    let options: [EditorialOption]
    let onSelect: (EditorialOption) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [EditorialOption] { search.isEmpty ? options : options.filter { $0.title.localizedStandardContains(search) } }
    var body: some View {
        NavigationStack {
            List(filtered) { option in Button(option.title) { onSelect(option); dismiss() }.foregroundStyle(.primary) }
                .searchable(text: $search)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}

private struct EditorialEventEditorView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let initialEvent: EditorialEvent

    @State private var detail: EditorialEventDetail?
    @State private var venues: [EditorialOption] = []
    @State private var title: String
    @State private var subtitle: String
    @State private var startDate: Date
    @State private var venueID: UUID
    @State private var imageURL: String
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var picker: EditorialPickerKind?
    @State private var selectedWork: EditorialEntity?

    init(auth: AuthStore, repository: EditorialRepository, initialEvent: EditorialEvent) {
        self.auth = auth
        self.repository = repository
        self.initialEvent = initialEvent
        _title = State(initialValue: initialEvent.title)
        _subtitle = State(initialValue: initialEvent.subtitle ?? "")
        _startDate = State(initialValue: initialEvent.startDate)
        _venueID = State(initialValue: initialEvent.venueID)
        _imageURL = State(initialValue: initialEvent.imageURL ?? "")
    }

    var body: some View {
        ZStack {
            EditorialBackground()
            ScrollView {
                VStack(spacing: 18) {
                    EditorialModeBanner(compact: true)
                    basicCard
                    participantsCard
                    programCard
                }
                .padding(16)
            }
            if isLoading || isSaving { Color.black.opacity(0.35).ignoresSafeArea(); ProgressView().tint(.orange).scaleEffect(1.25) }
        }
        .navigationTitle("Schnellkorrektur")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picker) { kind in
            EditorialOptionPicker(kind: kind, repository: repository, auth: auth) { option, role in
                Task { await apply(option: option, role: role, kind: kind) }
            }
        }
        .sheet(item: $selectedWork) { work in
            NavigationStack {
                EditorialEntityEditorView(auth: auth, repository: repository, entity: work) {
                    Task { await load() }
                }
            }
        }
        .alert("Korrektur nicht gespeichert", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await load() }
    }

    private var basicCard: some View {
        EditorialCard(title: "Basisdaten", icon: "pencil.and.list.clipboard") {
            EditorialTextField(label: "Titel", text: $title)
            EditorialTextField(label: "Untertitel", text: $subtitle)
            DatePicker("Tag und Uhrzeit", selection: $startDate)
                .datePickerStyle(.compact).tint(.orange).foregroundStyle(.white)
            Picker("Veranstaltungsort", selection: $venueID) {
                ForEach(venues) { Text($0.title).tag($0.id) }
            }.tint(.orange)
            EditorialTextField(label: "Bild-URL", text: $imageURL, axis: .vertical)
                .textInputAutocapitalization(.never).keyboardType(.URL)
            EditorialGalleryEditor(auth: auth, repository: repository, originType: "event", originID: initialEvent.id) { primaryURL in
                imageURL = primaryURL ?? ""
            }
            Button { Task { await saveBasics() } } label: {
                Label(message ?? "Änderungen zentral speichern", systemImage: message == nil ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditorialPrimaryButtonStyle()).disabled(isSaving)
            Text("Wird direkt in Supabase gespeichert und ist damit im Admin-Portal, in der Web-/Vercel-Ausgabe sowie in Flutter und Native verfügbar.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var participantsCard: some View {
        EditorialCard(title: "Mitwirkende", icon: "person.2.badge.gearshape") {
            if detail?.participants.isEmpty != false { Text("Keine Mitwirkenden hinterlegt").foregroundStyle(.secondary) }
            ForEach(detail?.participants ?? []) { participant in
                HStack {
                    VStack(alignment: .leading) { Text(participant.name); if let role = participant.roleLabel { Text(role).font(.caption).foregroundStyle(.orange) } }
                    Spacer()
                    Button(role: .destructive) { Task { await remove(participant) } } label: { Image(systemName: "trash") }
                }
                Divider()
            }
            HStack {
                Button("Person hinzufügen", systemImage: "person.badge.plus") { picker = .person }
                Button("Ensemble", systemImage: "person.3") { picker = .ensemble }
            }.buttonStyle(.bordered).tint(.orange)
        }
    }

    private var programCard: some View {
        EditorialCard(title: "Programm", icon: "music.note.list") {
            if detail?.works.isEmpty != false { Text("Kein strukturiertes Programm hinterlegt").foregroundStyle(.secondary) }
            ForEach(detail?.works ?? []) { link in
                HStack {
                    Button {
                        selectedWork = EditorialEntity(
                            id: link.workID,
                            kind: .work,
                            title: link.title,
                            subtitle: link.composer,
                            editableSubtitle: link.catalogNumber,
                            description: link.description,
                            imageURL: nil,
                            composerID: link.composerID
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(link.title)
                                if let composer = link.composer { Text(composer).font(.caption).foregroundStyle(.orange) }
                            }
                            Spacer()
                            Image(systemName: "pencil.circle").foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) { Task { await remove(link) } } label: { Image(systemName: "trash") }
                }
                Divider()
            }
            Button("Werk hinzufügen", systemImage: "plus") { picker = .work }
                .buttonStyle(.bordered).tint(.orange)
        }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true; defer { isLoading = false }
        do {
            async let loadedDetail = repository.detail(eventID: initialEvent.id, token: token)
            async let loadedVenues = repository.venues(token: token)
            detail = try await loadedDetail
            venues = try await loadedVenues
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func saveBasics(imageOverride: String? = nil) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isSaving = true; message = nil; defer { isSaving = false }
        do {
            try await repository.updateBasics(event: detail?.event ?? initialEvent, title: title, subtitle: subtitle, startDate: startDate, venueID: venueID, imageURL: imageOverride ?? imageURL, actor: actor, token: token)
            if let imageOverride { imageURL = imageOverride }
            message = "Gespeichert"
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func deleteEventImages() async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isSaving = true; message = nil; defer { isSaving = false }
        do {
            try await repository.deleteEventImages(event: detail?.event ?? initialEvent, actor: actor, token: token)
            imageURL = ""
            message = "Bild gelöscht"
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func apply(option: EditorialOption, role: String, kind: EditorialPickerKind) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        do {
            switch kind {
            case .person: try await repository.addParticipant(eventID: initialEvent.id, option: option, type: "person", role: role, actor: actor, token: token)
            case .ensemble: try await repository.addParticipant(eventID: initialEvent.id, option: option, type: "ensemble", role: role, actor: actor, token: token)
            case .work: try await repository.addWork(eventID: initialEvent.id, option: option, position: (detail?.works.map(\.position).max() ?? -1) + 1, actor: actor, token: token)
            }
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func remove(_ participant: EditorialParticipant) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        do { try await repository.removeParticipant(eventID: initialEvent.id, participant: participant, actor: actor, token: token); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func remove(_ link: EditorialWorkLink) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        do { try await repository.removeWork(eventID: initialEvent.id, link: link, actor: actor, token: token); await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private enum EditorialPickerKind: String, Identifiable { case person, ensemble, work; var id: String { rawValue }; var title: String { switch self { case .person: "Person auswählen"; case .ensemble: "Ensemble auswählen"; case .work: "Werk auswählen" } } }

private struct EditorialOptionPicker: View {
    let kind: EditorialPickerKind
    let repository: EditorialRepository
    @ObservedObject var auth: AuthStore
    let onSelect: (EditorialOption, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options: [EditorialOption] = []
    @State private var search = ""
    @State private var role = ""
    @State private var createKind: EditorialEntityKind?

    var filtered: [EditorialOption] { search.isEmpty ? options : options.filter { $0.title.localizedStandardContains(search) || ($0.subtitle?.localizedStandardContains(search) == true) } }
    var body: some View {
        NavigationStack {
            List {
                if kind != .work { TextField("Rolle, z. B. Dirigent:in", text: $role) }
                Section {
                    Button {
                        createKind = entityKind
                    } label: {
                        Label("Noch nicht vorhanden – neu anlegen", systemImage: "plus.circle.fill")
                    }
                    .foregroundStyle(.orange)
                }
                ForEach(filtered) { option in
                    Button { onSelect(option, role.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } label: {
                        VStack(alignment: .leading) { Text(option.title); if let subtitle = option.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
                    }.foregroundStyle(.primary)
                }
            }
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .sheet(item: $createKind) { newKind in
                EditorialCreateEntityView(auth: auth, repository: repository, kind: newKind) { entity in
                    let option = EditorialOption(id: entity.id, title: entity.title, subtitle: entity.subtitle)
                    onSelect(option, role.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
            }
            .task {
                guard let token = auth.accessToken else { return }
                options = (try? await { switch kind { case .person: try await repository.persons(token: token); case .ensemble: try await repository.ensembles(token: token); case .work: try await repository.works(token: token) } }()) ?? []
            }
        }
    }

    private var entityKind: EditorialEntityKind {
        switch kind {
        case .person: .person
        case .ensemble: .ensemble
        case .work: .work
        }
    }
}

private struct EditorialModeBanner: View {
    var compact = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("REDAKTIONSMODUS").font(.caption.bold()).tracking(1.5).foregroundStyle(.orange)
                if !compact { Text("Änderungen werden sofort plattformweit veröffentlicht.").font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
        }.padding(14).background(.orange.opacity(0.12), in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.45)) }
    }
}

private struct EditorialEventRow: View {
    let event: EditorialEvent
    var body: some View {
        HStack(spacing: 13) {
            AsyncImage(url: event.imageURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.08).overlay { Image(systemName: "photo") } }
                .frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 12)).clipped()
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.headline).lineLimit(2)
                Text(KlangradarDateTime.string(event.startDate, format: "EEE, d. MMM · HH:mm") + " · " + event.venueName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(); Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.orange)
        }
    }
}

private struct EditorialThumbnail: View {
    let url: String?
    let symbol: String
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: {
            Color.secondary.opacity(0.1).overlay { Image(systemName: symbol).foregroundStyle(.secondary) }
        }
        .frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 9)).clipped()
    }
}

private struct EditorialCard<Content: View>: View {
    let title: String; let icon: String; @ViewBuilder let content: Content
    init(title: String, icon: String, @ViewBuilder content: () -> Content) { self.title = title; self.icon = icon; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.orange)
            content
        }.padding(16).background(.regularMaterial, in: .rect(cornerRadius: 20)).overlay { RoundedRectangle(cornerRadius: 20).stroke(.separator.opacity(0.25)) }
    }
}

private struct EditorialTextField: View {
    let label: String; @Binding var text: String; var axis: Axis = .horizontal
    var body: some View { TextField(label, text: $text, axis: axis).padding(12).background(.secondary.opacity(0.08), in: .rect(cornerRadius: 11)).overlay { RoundedRectangle(cornerRadius: 11).stroke(.secondary.opacity(0.16)) } }
}

private struct EditorialGalleryEditor: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let originType: String
    let originID: UUID
    let onPrimaryChanged: (String?) -> Void

    @State private var images: [EditorialGalleryImage] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bildergalerie", systemImage: "photo.stack")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !images.isEmpty { Text("\(images.count)").font(.caption).foregroundStyle(.secondary) }
            }

            EditorialImagePickerButtons { selectedData in
                Task { await add(selectedData) }
            } onError: { errorMessage = $0 }

            if isWorking {
                ProgressView("Bilder werden verarbeitet …")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if images.isEmpty {
                Text("Noch keine Galeriebilder vorhanden.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: URL(string: image.url)) { loaded in
                                    loaded.resizable().scaledToFill()
                                } placeholder: {
                                    Color.secondary.opacity(0.1).overlay { ProgressView() }
                                }
                                .frame(width: 180, height: 112)
                                .clipShape(.rect(cornerRadius: 12)).clipped()

                                if index == 0 {
                                    Label("Titelbild", systemImage: "star.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                } else {
                                    Button("Als Titelbild", systemImage: "star") { Task { await makePrimary(image) } }
                                        .font(.caption)
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { Task { await delete(image) } }
                                    .font(.caption)
                            }
                            .padding(10)
                            .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
                        }
                    }
                }
            }
        }
        .task { await load() }
        .alert("Bilder konnten nicht geändert werden", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { return }
        do {
            images = try await repository.galleryImages(originType: originType, originID: originID, token: token)
            if let primaryURL = images.first?.url { onPrimaryChanged(primaryURL) }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func add(_ data: [Data]) async {
        guard let token = auth.accessToken, let actor = auth.userID, !data.isEmpty else { return }
        isWorking = true; defer { isWorking = false }
        do {
            images = try await repository.addGalleryImages(data: data, originType: originType, originID: originID, actor: actor, token: token)
            onPrimaryChanged(images.first?.url)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func makePrimary(_ image: EditorialGalleryImage) async {
        guard let token = auth.accessToken else { return }
        isWorking = true; defer { isWorking = false }
        do {
            try await repository.setPrimaryGalleryImage(image, originType: originType, originID: originID, token: token)
            images = try await repository.galleryImages(originType: originType, originID: originID, token: token)
            onPrimaryChanged(images.first?.url)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func delete(_ image: EditorialGalleryImage) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isWorking = true; defer { isWorking = false }
        do {
            images = try await repository.deleteGalleryImage(image, originType: originType, originID: originID, actor: actor, token: token)
            onPrimaryChanged(images.first?.url)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct EditorialImagePickerButtons: View {
    let onImages: ([Data]) -> Void
    let onError: (String) -> Void
    var allowsMultipleSelection = true
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showsFileImporter = false
    @State private var isPreparing = false

    var body: some View {
        HStack {
            PhotosPicker(selection: $photoItems, maxSelectionCount: allowsMultipleSelection ? 20 : 1, matching: .images) {
                Label("Fotomediathek", systemImage: "photo.on.rectangle")
            }
            Button("Dateien", systemImage: "folder") { showsFileImporter = true }
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .disabled(isPreparing)
        .overlay(alignment: .trailing) { if isPreparing { ProgressView() } }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                isPreparing = true
                defer { isPreparing = false; photoItems = [] }
                do {
                    var prepared: [Data] = []
                    for item in items {
                        guard let data = try await item.loadTransferable(type: Data.self), let jpeg = Self.preparedJPEG(from: data) else {
                            throw EditorialImageError.unreadable
                        }
                        prepared.append(jpeg)
                    }
                    onImages(prepared)
                } catch { onError(error.localizedDescription) }
            }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: allowsMultipleSelection) { result in
            do {
                let urls = try result.get()
                var prepared: [Data] = []
                for url in urls {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let jpeg = Self.preparedJPEG(from: data) else { throw EditorialImageError.unreadable }
                    prepared.append(jpeg)
                }
                onImages(prepared)
            } catch { onError(error.localizedDescription) }
        }
    }

    private static func preparedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximumDimension: CGFloat = 2400
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / longestSide)
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.86)
    }
}

private enum EditorialImageError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Das ausgewählte Bild konnte nicht verarbeitet werden." }
}

private struct EditorialPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.fontWeight(.semibold).padding(13).background(.orange.opacity(configuration.isPressed ? 0.7 : 1), in: .rect(cornerRadius: 12)).foregroundStyle(.black) }
}

private struct EditorialBackground: View {
    var body: some View { KlangradarBackground().ignoresSafeArea() }
}
