import PhotosUI
import SwiftUI

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

/// UIImage ist nicht Identifiable — Wrapper für .sheet(item:).
private struct CropImagePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Bearbeitung von Personen/Ensembles/Venues/Werken — vom Dashboard aus
/// erreichbar, daher `internal` statt `private`.
struct EditorialEntityEditorView: View {
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

    // Punkt 19, natives Bild-Crop
    @State private var avatarCrop: CropRect?
    @State private var cropPayload: CropImagePayload?
    @State private var isLoadingCropImage = false

    init(auth: AuthStore, repository: EditorialRepository, entity: EditorialEntity, onSaved: @escaping () -> Void = {}) {
        self.auth = auth; self.repository = repository; self.entity = entity
        self.onSaved = onSaved
        _avatarCrop = State(initialValue: entity.avatarCrop)
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
                HStack(spacing: 12) {
                    CroppedAsyncImage(url: url, crop: avatarCrop) {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: 88, height: 88).clipShape(Circle()).clipped()

                    Button {
                        Task { await beginCrop(url: url) }
                    } label: {
                        if isLoadingCropImage { ProgressView() }
                        else { Label("Ausschnitt festlegen", systemImage: "crop") }
                    }
                    .buttonStyle(.bordered).tint(KlangradarTheme.accent)
                    .disabled(isLoadingCropImage)
                }
                .sheet(item: $cropPayload) { payload in
                    EditorialImageCropView(
                        image: payload.image, initialCrop: avatarCrop, aspect: 1, isCircular: true,
                        title: "Rundes Profilfoto: Ausschnitt festlegen",
                        onSave: { crop in
                            guard let actor = auth.userID, let token = auth.accessToken else {
                                throw EditorialError.validation("Bitte zuerst anmelden.")
                            }
                            try await repository.updateAvatarCrop(entity: entity, crop: crop, actor: actor, token: token)
                            avatarCrop = crop
                        },
                        onReset: {
                            guard let actor = auth.userID, let token = auth.accessToken else {
                                throw EditorialError.validation("Bitte zuerst anmelden.")
                            }
                            try await repository.updateAvatarCrop(entity: entity, crop: nil, actor: actor, token: token)
                            avatarCrop = nil
                        }
                    )
                }
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
            RecentlyEditedStore.shared.record(kind: RecentlyEditedItem.Kind(entity.kind), id: entity.id, title: title)
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

    @MainActor private func beginCrop(url: URL) async {
        isLoadingCropImage = true; defer { isLoadingCropImage = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else {
                errorMessage = "Bild konnte nicht geladen werden."
                return
            }
            cropPayload = CropImagePayload(image: uiImage)
        } catch { errorMessage = error.localizedDescription }
    }

}
