import PhotosUI
import SwiftUI

/// Neuanlage von Personen/Ensembles/Werken direkt aus der Redaktion —
/// sowohl vom Dashboard (Plus-Button) als auch aus einem Auswahl-Picker
/// heraus erreichbar (EventEditor's EditorialOptionPicker, "noch nicht
/// vorhanden – neu anlegen"), daher `internal` statt `private`.
struct EditorialCreateEntityView: View {
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
                try await repository.updateEntity(entity: entity, title: entity.title, subtitle: subtitle, description: description, imageURL: profileURL.absoluteString, composerID: composerID, actor: actor, token: token)
                createdEntity = EditorialEntity(id: entity.id, kind: kind, title: entity.title, subtitle: entity.subtitle, editableSubtitle: entity.editableSubtitle, description: entity.description, imageURL: profileURL.absoluteString, composerID: entity.composerID)
            }
            if !pendingImageData.isEmpty {
                _ = try await repository.addGalleryImages(data: pendingImageData, originType: kind.rawValue, originID: entity.id, actor: actor, token: token)
            }
            RecentlyEditedStore.shared.record(kind: RecentlyEditedItem.Kind(kind), id: createdEntity.id, title: createdEntity.title)
            onCreated(createdEntity)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
