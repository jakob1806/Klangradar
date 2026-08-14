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
                EditorialScopePicker(selection: $scope)
                    .padding(.vertical, 8)

                Group {
                if isLoading { ProgressView("Redaktionsdaten werden geladen …").tint(KlangradarTheme.accent) }
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

            Section {
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
            } header: {
                HStack {
                    Text(scope.title)
                    Spacer()
                    Text("\(scope == .events ? filteredEvents.count : filteredEntities.count)")
                        .foregroundStyle(.secondary)
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

private struct EditorialScopePicker: View {
    @Binding var selection: EditorialScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorialScope.allCases) { scope in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { selection = scope }
                    } label: {
                        Label(scope.title, systemImage: scope.symbol)
                            .font(.subheadline.weight(selection == scope ? .semibold : .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .foregroundStyle(selection == scope ? Color.white : Color.primary)
                            .background(selection == scope ? KlangradarTheme.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == scope ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(.ultraThinMaterial)
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

private enum EditorialEntityPickerKind: Identifiable {
    case composer, memberOfEnsemble, homeVenue, parentEnsemble
    var id: Self { self }
    var title: String {
        switch self {
        case .composer: "Komponist:in"
        case .memberOfEnsemble, .homeVenue: "Ensemble/Venue"
        case .parentEnsemble: "Übergeordnetes Ensemble"
        }
    }
}

private let EDITORIAL_ENSEMBLE_TYPE_OPTIONS: [(value: String, label: String)] = [
    ("chor", "Chor"), ("orchester", "Orchester"), ("kammerensemble", "Kammerensemble"),
    ("big_band", "Big Band"), ("sonstiges", "Sonstiges")
]

private struct EditorialEntityEditorView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let entity: EditorialEntity
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var subtitle: String
    @State private var description: String
    @State private var imageURL: String
    @State private var composerID: UUID?
    @State private var composerName: String?
    @State private var persons: [EditorialOption] = []
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var picker: EditorialEntityPickerKind?

    // Feldparität — gemeinsam
    @State private var slug: String
    @State private var websiteURL: String
    @State private var isVerified: Bool

    // Venue
    @State private var addressStreet: String
    @State private var addressZip: String
    @State private var addressCity: String
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var capacityText: String

    // Person
    @State private var firstName: String
    @State private var middleName: String
    @State private var lastName: String
    @State private var rolesText: String
    @State private var nationality: String
    @State private var birthDateText: String
    @State private var deathDateText: String
    @State private var isDeceased: Bool
    @State private var memberOfEnsembleID: UUID?
    @State private var memberOfEnsembleName: String?

    // Ensemble
    @State private var ensembleType: String
    @State private var foundedYearText: String
    @State private var memberCountText: String
    @State private var homeVenueID: UUID?
    @State private var homeVenueName: String?
    @State private var parentEnsembleID: UUID?
    @State private var parentEnsembleName: String?

    @State private var venueOptions: [EditorialOption] = []
    @State private var ensembleOptions: [EditorialOption] = []

    init(auth: AuthStore, repository: EditorialRepository, entity: EditorialEntity, onSaved: @escaping () -> Void = {}) {
        self.auth = auth; self.repository = repository; self.entity = entity
        self.onSaved = onSaved
        _title = State(initialValue: entity.title)
        _subtitle = State(initialValue: entity.editableSubtitle ?? "")
        _description = State(initialValue: entity.description ?? "")
        _imageURL = State(initialValue: entity.imageURL ?? "")
        _composerID = State(initialValue: entity.composerID)
        _slug = State(initialValue: entity.slug ?? "")
        _websiteURL = State(initialValue: entity.websiteURL ?? "")
        _isVerified = State(initialValue: entity.isVerified ?? false)
        _addressStreet = State(initialValue: entity.addressStreet ?? "")
        _addressZip = State(initialValue: entity.addressZip ?? "")
        _addressCity = State(initialValue: entity.addressCity ?? "München")
        _latitudeText = State(initialValue: entity.latitude.map { String($0) } ?? "")
        _longitudeText = State(initialValue: entity.longitude.map { String($0) } ?? "")
        _capacityText = State(initialValue: entity.capacity.map { String($0) } ?? "")
        _firstName = State(initialValue: entity.firstName ?? "")
        _middleName = State(initialValue: entity.middleName ?? "")
        _lastName = State(initialValue: entity.lastName ?? "")
        _rolesText = State(initialValue: (entity.roles ?? []).joined(separator: ", "))
        _nationality = State(initialValue: entity.nationality ?? "")
        _birthDateText = State(initialValue: entity.birthDate ?? "")
        _deathDateText = State(initialValue: entity.deathDate ?? "")
        _isDeceased = State(initialValue: entity.isDeceased ?? false)
        _memberOfEnsembleID = State(initialValue: entity.memberOfEnsembleID)
        _ensembleType = State(initialValue: entity.ensembleType ?? "sonstiges")
        _foundedYearText = State(initialValue: entity.foundedYear.map { String($0) } ?? "")
        _memberCountText = State(initialValue: entity.memberCount.map { String($0) } ?? "")
        _homeVenueID = State(initialValue: entity.homeVenueID)
        _parentEnsembleID = State(initialValue: entity.parentEnsembleID)
    }

    var body: some View {
        Form {
            Section {
                EditorialModeBanner(compact: true)
            }
            masterDataSection
            if entity.kind != .work { extendedFieldsSection }
            Section { EditorialAIAssistantView(auth: auth, repository: repository, entityType: entity.kind.rawValue, entityID: entity.id) }
            imagesSection
            saveSection
            if entity.kind != .work { deleteSection }
        }
        .scrollContentBackground(.hidden)
        .background(EditorialBackground())
        .navigationTitle(entity.kind.singularTitle + " bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(saved ? "Gespeichert" : "Speichern", systemImage: saved ? "checkmark" : "icloud.and.arrow.up") {
                    Task { await save() }
                }
                .disabled(isSaving || isDeleting)
            }
        }
        .disabled(isSaving || isDeleting)
        .overlay { if isSaving || isDeleting { ProgressView() } }
        .sheet(item: $picker) { kind in
            EditorialSimpleOptionPicker(title: kind.title, options: pickerOptions(for: kind)) { option in
                apply(option: option, to: kind)
            }
        }
        .alert("Änderung nicht gespeichert", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(
            "\(entity.title) endgültig löschen?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("\(entity.kind.singularTitle) löschen", role: .destructive) { Task { await deleteEntity() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Verknüpfte Veranstaltungen, Quellen und Kandidaten werden entkoppelt, nicht mitgelöscht. Dieser Schritt kann nicht rückgängig gemacht werden.")
        }
        .task {
            guard let token = auth.accessToken else { return }
            if entity.kind == .work {
                persons = (try? await repository.persons(token: token)) ?? []
                composerName = persons.first { $0.id == composerID }?.title
            }
            if entity.kind == .person {
                ensembleOptions = (try? await repository.ensembles(token: token)) ?? []
                memberOfEnsembleName = ensembleOptions.first { $0.id == memberOfEnsembleID }?.title
            }
            if entity.kind == .ensemble {
                venueOptions = (try? await repository.venues(token: token)) ?? []
                ensembleOptions = (try? await repository.ensembles(token: token)) ?? []
                homeVenueName = venueOptions.first { $0.id == homeVenueID }?.title
                parentEnsembleName = ensembleOptions.first { $0.id == parentEnsembleID }?.title
            }
        }
    }

    private func pickerOptions(for kind: EditorialEntityPickerKind) -> [EditorialOption] {
        switch kind {
        case .composer: persons
        case .memberOfEnsemble: ensembleOptions
        case .homeVenue: venueOptions
        case .parentEnsemble: ensembleOptions.filter { $0.id != entity.id }
        }
    }

    private func apply(option: EditorialOption, to kind: EditorialEntityPickerKind) {
        switch kind {
        case .composer: composerID = option.id; composerName = option.title
        case .memberOfEnsemble: memberOfEnsembleID = option.id; memberOfEnsembleName = option.title
        case .homeVenue: homeVenueID = option.id; homeVenueName = option.title
        case .parentEnsemble: parentEnsembleID = option.id; parentEnsembleName = option.title
        }
    }

    private var titleLabel: String { entity.kind == .work ? "Werktitel" : entity.kind == .person ? "Name" : entity.kind == .venue ? "Venue-Name" : "Ensemble-Name" }
    private var descriptionLabel: String { entity.kind == .person ? "Biografie" : "Beschreibung" }

    private var masterDataSection: some View {
        Section("Stammdaten") {
            if entity.kind == .person {
                TextField("Vorname", text: $firstName)
                TextField("Zweiter Vorname", text: $middleName)
                TextField("Nachname", text: $lastName)
            } else {
                TextField(titleLabel, text: $title)
            }
            if entity.kind == .person { TextField("Instrument", text: $subtitle) }
            if entity.kind == .work {
                TextField("Werkverzeichnis", text: $subtitle)
                Button { picker = .composer } label: {
                    LabeledContent("Komponist:in", value: composerName ?? "Auswählen")
                }.foregroundStyle(.primary)
            }
            TextField(descriptionLabel, text: $description, axis: .vertical)
                .lineLimit(4...12)
        }
    }

    /// Feldparität mit den Web-Admin-Formularen (siehe EditorialEntity-
    /// Kommentar) — pro Kind eingeblendet, ein Werk hat hier nichts
    /// Zusätzliches (bereits vollständig in masterDataSection).
    @ViewBuilder private var extendedFieldsSection: some View {
        Section("Weitere Angaben") {
            TextField("Slug (URL)", text: $slug)
                .textInputAutocapitalization(.never)

            if entity.kind == .venue {
                TextField("Straße & Hausnummer", text: $addressStreet)
                TextField("PLZ", text: $addressZip)
                TextField("Stadt", text: $addressCity)
                TextField("Breitengrad (lat)", text: $latitudeText).keyboardType(.decimalPad)
                TextField("Längengrad (lng)", text: $longitudeText).keyboardType(.decimalPad)
                TextField("Kapazität", text: $capacityText).keyboardType(.numberPad)
            }

            if entity.kind == .person {
                // Freies Feld statt fester Rollen-Checkboxen (Nutzervorgabe:
                // auch Regisseur/Schauspieler/etc. sollen möglich sein,
                // persons.roles ist seit 20261013000014 text[] statt Enum).
                TextField("Rollen (kommagetrennt, z.B. solist, regisseur)", text: $rolesText)
                Button { picker = .memberOfEnsemble } label: {
                    LabeledContent("Gehört zu Ensemble", value: memberOfEnsembleName ?? "— kein Ensemble —")
                }.foregroundStyle(.primary)
                TextField("Nationalität", text: $nationality)
                TextField("Geburtsdatum (JJJJ-MM-TT)", text: $birthDateText).keyboardType(.numbersAndPunctuation)
                TextField("Sterbedatum (JJJJ-MM-TT)", text: $deathDateText).keyboardType(.numbersAndPunctuation)
                Toggle("Verstorben (auch ohne bekanntes genaues Datum)", isOn: $isDeceased)
            }

            if entity.kind == .ensemble {
                Picker("Typ", selection: $ensembleType) {
                    ForEach(EDITORIAL_ENSEMBLE_TYPE_OPTIONS, id: \.value) { Text($0.label).tag($0.value) }
                }
                TextField("Gründungsjahr", text: $foundedYearText).keyboardType(.numberPad)
                TextField("Mitgliederzahl", text: $memberCountText).keyboardType(.numberPad)
                Button { picker = .homeVenue } label: {
                    LabeledContent("Heimat-Venue", value: homeVenueName ?? "—")
                }.foregroundStyle(.primary)
                Button { picker = .parentEnsemble } label: {
                    LabeledContent("Gehört zu Ensemble", value: parentEnsembleName ?? "— kein übergeordnetes Ensemble —")
                }.foregroundStyle(.primary)
            }

            TextField("Website", text: $websiteURL).textInputAutocapitalization(.never).keyboardType(.URL)
            if entity.kind != .venue {
                Toggle("Redaktionell geprüft", isOn: $isVerified)
            }
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
        let effectiveImageURL = imageOverride ?? imageURL
        do {
            switch entity.kind {
            case .venue:
                try await repository.updateVenue(
                    entity: entity, name: title, slug: slug, description: description,
                    addressStreet: addressStreet, addressZip: addressZip, addressCity: addressCity,
                    latitude: Double(latitudeText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                    longitude: Double(longitudeText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                    capacity: Int(capacityText), websiteURL: websiteURL, imageURL: effectiveImageURL,
                    actor: actor, token: token
                )
            case .person:
                try await repository.updatePersonDetails(
                    entity: entity, firstName: firstName, middleName: middleName, lastName: lastName, slug: slug,
                    instrument: subtitle, biographyDe: description, imageURL: effectiveImageURL,
                    roles: rolesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty },
                    nationality: nationality, birthDate: birthDateText, deathDate: deathDateText,
                    isDeceased: isDeceased, memberOfEnsembleID: memberOfEnsembleID, websiteURL: websiteURL, isVerified: isVerified,
                    actor: actor, token: token
                )
            case .ensemble:
                try await repository.updateEntity(entity: entity, title: title, subtitle: subtitle, description: description, imageURL: effectiveImageURL, composerID: composerID, actor: actor, token: token)
                try await repository.updateEnsembleDetails(
                    entity: entity, slug: slug, type: ensembleType, foundedYear: Int(foundedYearText), memberCount: Int(memberCountText),
                    homeVenueID: homeVenueID, parentEnsembleID: parentEnsembleID, websiteURL: websiteURL, isVerified: isVerified,
                    actor: actor, token: token
                )
            case .work:
                try await repository.updateEntity(entity: entity, title: title, subtitle: subtitle, description: description, imageURL: effectiveImageURL, composerID: composerID, actor: actor, token: token)
            }
            if let imageOverride { imageURL = imageOverride }
            saved = true
            onSaved()
        } catch { errorMessage = error.localizedDescription }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                Label("\(entity.kind.singularTitle) löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text("Löscht den Eintrag dauerhaft aus allen Klangradar-Anwendungen.")
        }
    }

    @MainActor private func deleteEntity() async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isDeleting = true
        do {
            try await repository.deleteEntity(entity, actor: actor, token: token)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isDeleting = false
        }
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

private struct EditorialAIAssistantView: View {
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

private enum EditorialEventEditorSection: String, CaseIterable, Identifiable {
    case event, program, research
    var id: Self { self }
    var title: String {
        switch self { case .event: "Daten"; case .program: "Besetzung"; case .research: "KI" }
    }
    var symbol: String {
        switch self { case .event: "doc.text"; case .program: "person.2"; case .research: "sparkles" }
    }
}

private struct EditorialEventSectionPicker: View {
    @Binding var selection: EditorialEventEditorSection

    var body: some View {
        HStack(spacing: 5) {
            ForEach(EditorialEventEditorSection.allCases) { section in
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = section }
                } label: {
                    Label(section.title, systemImage: section.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selection == section ? Color.white : Color.secondary)
                        .background(selection == section ? KlangradarTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.18)) }
    }
}

private struct EditorialGenrePicker: View {
    let options: [EditorialOption]
    @Binding var selection: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [EditorialOption] {
        search.isEmpty
            ? options
            : options.filter { $0.title.localizedStandardContains(search) || ($0.subtitle?.localizedStandardContains(search) == true) }
    }

    var body: some View {
        NavigationStack {
            List {
                if selection.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Genres gewählt",
                        systemImage: "music.quarternote.3",
                        description: Text("Suche frei nach einem Genre und wähle beliebig viele aus.")
                    )
                    .listRowBackground(Color.clear)
                }
                Section(selection.isEmpty ? "Alle Genres" : "Genres · \(selection.count) ausgewählt") {
                    ForEach(filtered) { genre in
                        Button {
                            if selection.contains(genre.id) { selection.remove(genre.id) }
                            else { selection.insert(genre.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(genre.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(genre.id) ? KlangradarTheme.accent : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(genre.title).foregroundStyle(.primary)
                                    if let subtitle = genre.subtitle {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Genre suchen")
            .navigationTitle("Genres auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !selection.isEmpty { Button("Alle entfernen") { selection.removeAll() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct EditorialEventEditorView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let initialEvent: EditorialEvent

    @Environment(\.dismiss) private var dismiss

    @State private var detail: EditorialEventDetail?
    @State private var venues: [EditorialOption] = []
    @State private var title: String
    @State private var subtitle: String
    @State private var startDate: Date
    @State private var venueID: UUID
    @State private var imageURL: String
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var picker: EditorialPickerKind?
    @State private var selectedWork: EditorialEntity?
    @State private var showsDeleteConfirmation = false

    // Feldparität mit event-form.tsx
    @State private var descriptionDe: String = ""
    @State private var durationMinutesText: String = ""
    @State private var hasIntermission: Bool = false
    @State private var organizerID: UUID?
    @State private var organizerName: String?
    @State private var organizerOptions: [EditorialOption] = []
    @State private var showsOrganizerPicker = false
    @State private var showsGenrePicker = false
    @State private var editorSection: EditorialEventEditorSection = .event
    @State private var genreOptions: [EditorialOption] = []
    @State private var selectedGenreIDs: Set<UUID> = []
    @State private var priceMinText: String = ""
    @State private var priceMaxText: String = ""
    @State private var isFree: Bool = false
    @State private var ticketURL: String = ""
    @State private var remainingTicketsStatus: String = ""
    @State private var doorsInfo: String = ""
    @State private var ageRestriction: String = ""
    @State private var discountInfo: String = ""
    @State private var presaleFeeInfo: String = ""
    @State private var status: String = "scheduled"
    @State private var isSavingDetails = false
    @State private var detailsMessage: String?

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

    /// Erweiterte Felder kommen erst mit detail(eventID:) (die Listen-Query
    /// in events() lädt sie aus Performancegründen nicht mit) — deshalb hier
    /// aus dem geladenen EditorialEventDetail befüllt statt schon im init().
    @MainActor private func syncDetailFields(from event: EditorialEvent) {
        descriptionDe = event.descriptionDe ?? ""
        durationMinutesText = event.durationMinutes.map { String($0) } ?? ""
        hasIntermission = event.hasIntermission
        organizerID = event.organizerID
        organizerName = organizerOptions.first { $0.id == event.organizerID }?.title
        selectedGenreIDs = Set(event.genreIDs)
        priceMinText = event.priceMin.map { String($0) } ?? ""
        priceMaxText = event.priceMax.map { String($0) } ?? ""
        isFree = event.isFree
        ticketURL = event.ticketURL ?? ""
        remainingTicketsStatus = event.remainingTicketsStatus ?? ""
        doorsInfo = event.doorsInfo ?? ""
        ageRestriction = event.ageRestriction ?? ""
        discountInfo = event.discountInfo ?? ""
        presaleFeeInfo = event.presaleFeeInfo ?? ""
        status = event.status
    }

    var body: some View {
        ZStack {
            EditorialBackground()
            ScrollView {
                VStack(spacing: 16) {
                    EditorialModeBanner(compact: true)
                    EditorialEventSectionPicker(selection: $editorSection)
                    Group {
                        switch editorSection {
                        case .event:
                            basicCard
                            detailsCard
                        case .program:
                            participantsCard
                            programCard
                        case .research:
                            EditorialAIAssistantView(auth: auth, repository: repository, entityType: "event", entityID: initialEvent.id)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .padding(16)
            }
            if isLoading || isSaving || isDeleting { Color.black.opacity(0.22).ignoresSafeArea(); ProgressView().tint(KlangradarTheme.accent).scaleEffect(1.25) }
        }
        .navigationTitle("Veranstaltung bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Veranstaltung löschen", systemImage: "trash", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
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
        .sheet(isPresented: $showsOrganizerPicker) {
            EditorialSimpleOptionPicker(title: "Veranstalter", options: organizerOptions) { option in
                organizerID = option.id; organizerName = option.title
            }
        }
        .sheet(isPresented: $showsGenrePicker) {
            EditorialGenrePicker(options: genreOptions, selection: $selectedGenreIDs)
        }
        .alert("Korrektur nicht gespeichert", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(
            "\(initialEvent.title) endgültig löschen?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Veranstaltung löschen", role: .destructive) { Task { await deleteEvent() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Mitwirkende- und Programm-Verknüpfungen werden mitgelöscht. Dieser Schritt kann nicht rückgängig gemacht werden.")
        }
        .task { await load() }
    }

    private var basicCard: some View {
        EditorialCard(title: "Basisdaten", icon: "pencil.and.list.clipboard") {
            EditorialTextField(label: "Titel", text: $title)
            EditorialTextField(label: "Untertitel", text: $subtitle)
            DatePicker("Tag und Uhrzeit", selection: $startDate)
                .datePickerStyle(.compact).tint(KlangradarTheme.accent)
            Picker("Veranstaltungsort", selection: $venueID) {
                ForEach(venues) { Text($0.title).tag($0.id) }
            }.tint(KlangradarTheme.accent)
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

    private static let STATUS_OPTIONS: [(value: String, label: String)] = [
        ("scheduled", "Geplant"), ("sold_out", "Ausverkauft"), ("cancelled", "Abgesagt"),
        ("postponed", "Verschoben"), ("draft", "Entwurf (nicht öffentlich)")
    ]
    private static let TICKET_STATUS_OPTIONS: [(value: String, label: String)] = [
        ("", "— (unbekannt)"), ("available", "Verfügbar"), ("few_left", "Nur noch wenige"),
        ("sold_out", "Ausverkauft"), ("box_office_only", "Nur Abendkasse")
    ]

    /// Feldparität mit event-form.tsx, ergänzend zur "Schnellkorrektur"
    /// (basicCard) — eigene Karte mit eigenem Speichern-Button, damit die
    /// bestehende Schnellkorrektur unverändert nutzbar bleibt.
    private var detailsCard: some View {
        EditorialCard(title: "Weitere Angaben", icon: "list.bullet.rectangle") {
            EditorialTextField(label: "Beschreibung", text: $descriptionDe, axis: .vertical)
            EditorialTextField(label: "Dauer (Minuten)", text: $durationMinutesText)
                .keyboardType(.numberPad)
            Toggle("Mit Pause", isOn: $hasIntermission).tint(KlangradarTheme.accent)

            HStack {
                Button { showsOrganizerPicker = true } label: {
                    LabeledContent("Veranstalter", value: organizerName ?? "—").foregroundStyle(.primary)
                }
                if organizerID != nil {
                    Button { organizerID = nil; organizerName = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button { showsGenrePicker = true } label: {
                    HStack {
                        Label("Genres", systemImage: "music.quarternote.3")
                        Spacer()
                        Text(selectedGenreIDs.isEmpty ? "Auswählen" : "\(selectedGenreIDs.count) gewählt")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
                if !selectedGenreIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(genreOptions.filter { selectedGenreIDs.contains($0.id) }) { genre in
                                HStack(spacing: 5) {
                                    Text(genre.title)
                                    Button { selectedGenreIDs.remove(genre.id) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(KlangradarTheme.accent.opacity(0.12), in: Capsule())
                                .foregroundStyle(KlangradarTheme.accent)
                            }
                        }
                    }
                }
            }

            EditorialTextField(label: "Preis von (€)", text: $priceMinText).keyboardType(.decimalPad)
            EditorialTextField(label: "Preis bis (€)", text: $priceMaxText).keyboardType(.decimalPad)
            Toggle("Kostenlos", isOn: $isFree).tint(KlangradarTheme.accent)
            EditorialTextField(label: "Ticket-Link", text: $ticketURL).textInputAutocapitalization(.never).keyboardType(.URL)

            Picker("Ticket-Status", selection: $remainingTicketsStatus) {
                ForEach(Self.TICKET_STATUS_OPTIONS, id: \.value) { Text($0.label).tag($0.value) }
            }.tint(KlangradarTheme.accent)

            EditorialTextField(label: "Einlass", text: $doorsInfo)
            EditorialTextField(label: "Altersbeschränkung", text: $ageRestriction)
            EditorialTextField(label: "Ermäßigung", text: $discountInfo)
            EditorialTextField(label: "Vorverkaufsgebühr", text: $presaleFeeInfo)

            Picker("Status", selection: $status) {
                ForEach(Self.STATUS_OPTIONS, id: \.value) { Text($0.label).tag($0.value) }
            }.tint(KlangradarTheme.accent)

            Button { Task { await saveDetails() } } label: {
                Label(detailsMessage ?? "Weitere Angaben speichern", systemImage: detailsMessage == nil ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditorialPrimaryButtonStyle()).disabled(isSavingDetails)
        }
    }

    private var participantsCard: some View {
        EditorialCard(title: "Mitwirkende", icon: "person.2.badge.gearshape") {
            if detail?.participants.isEmpty != false { Text("Keine Mitwirkenden hinterlegt").foregroundStyle(.secondary) }
            ForEach(detail?.participants ?? []) { participant in
                HStack {
                    VStack(alignment: .leading) { Text(participant.name); if let role = participant.roleLabel { Text(role).font(.caption).foregroundStyle(KlangradarTheme.accent) } }
                    Spacer()
                    Button(role: .destructive) { Task { await remove(participant) } } label: { Image(systemName: "trash") }
                }
                Divider()
            }
            HStack {
                Button("Person hinzufügen", systemImage: "person.badge.plus") { picker = .person }
                Button("Ensemble", systemImage: "person.3") { picker = .ensemble }
            }.buttonStyle(.bordered).tint(KlangradarTheme.accent)
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
                                if let composer = link.composer { Text(composer).font(.caption).foregroundStyle(KlangradarTheme.accent) }
                            }
                            Spacer()
                            Image(systemName: "pencil.circle").foregroundStyle(KlangradarTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) { Task { await remove(link) } } label: { Image(systemName: "trash") }
                }
                Divider()
            }
            Button("Werk hinzufügen", systemImage: "plus") { picker = .work }
                .buttonStyle(.bordered).tint(KlangradarTheme.accent)
        }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { return }
        isLoading = true; defer { isLoading = false }
        do {
            async let loadedDetail = repository.detail(eventID: initialEvent.id, token: token)
            async let loadedVenues = repository.venues(token: token)
            async let loadedOrganizers = repository.organizers(token: token)
            async let loadedGenres = repository.genres(token: token)
            detail = try await loadedDetail
            venues = try await loadedVenues
            organizerOptions = try await loadedOrganizers
            genreOptions = try await loadedGenres
            if let event = detail?.event { syncDetailFields(from: event) }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func saveDetails() async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isSavingDetails = true; detailsMessage = nil; defer { isSavingDetails = false }
        do {
            try await repository.updateEventDetails(
                event: detail?.event ?? initialEvent, descriptionDe: descriptionDe, durationMinutes: Int(durationMinutesText),
                hasIntermission: hasIntermission, organizerID: organizerID, genreIDs: Array(selectedGenreIDs),
                priceMin: Double(priceMinText.replacingOccurrences(of: ",", with: ".")), priceMax: Double(priceMaxText.replacingOccurrences(of: ",", with: ".")),
                isFree: isFree, ticketURL: ticketURL, remainingTicketsStatus: remainingTicketsStatus, doorsInfo: doorsInfo,
                ageRestriction: ageRestriction, discountInfo: discountInfo, presaleFeeInfo: presaleFeeInfo, status: status,
                actor: actor, token: token
            )
            detailsMessage = "Gespeichert"
            await load()
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

    @MainActor private func deleteEvent() async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isDeleting = true
        do {
            try await repository.deleteEvent(detail?.event ?? initialEvent, actor: actor, token: token)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isDeleting = false
        }
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
                    .foregroundStyle(KlangradarTheme.accent)
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
            Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("REDAKTIONSMODUS").font(.caption.bold()).tracking(1.3).foregroundStyle(.orange)
                    Text("LIVE").font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.orange.opacity(0.16), in: Capsule()).foregroundStyle(.orange)
                }
                if !compact { Text("Änderungen werden sofort plattformweit veröffentlicht.").font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.35)) }
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
            Spacer(); Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(KlangradarTheme.accent)
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(KlangradarTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(KlangradarTheme.accent)
                Text(title).font(.headline).foregroundStyle(.primary)
            }
            content
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.separator.opacity(0.18)) }
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

private struct EditorialTextField: View {
    let label: String; @Binding var text: String; var axis: Axis = .horizontal
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField(label, text: $text, axis: axis)
                .padding(12)
                .background(.background.opacity(0.72), in: .rect(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(.separator.opacity(0.3)) }
        }
    }
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
                                        .font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
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
        .tint(KlangradarTheme.accent)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(13)
            .background(KlangradarTheme.accent.opacity(configuration.isPressed ? 0.72 : 1), in: .rect(cornerRadius: 12))
            .foregroundStyle(.white)
    }
}

private struct EditorialBackground: View {
    var body: some View { KlangradarBackground().ignoresSafeArea() }
}
