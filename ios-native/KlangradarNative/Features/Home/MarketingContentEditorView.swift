import PhotosUI
import SwiftUI

/// Inline-Bildfeld: Vorschau + „Aus Fotos wählen" + URL-Textfeld — beide
/// schreiben in dasselbe `imagePath` (lokale Datei vs. http(s)-URL wird über
/// `MarketingContentStore.resolvedURL(for:)` unterschieden).
private struct MarketingImageField: View {
    @EnvironmentObject private var store: MarketingContentStore
    @Binding var imagePath: String?
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: MarketingContentStore.resolvedURL(for: imagePath)) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.12).overlay { Image(systemName: "photo") }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 10))
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                TextField("Bild-URL (https://…)", text: Binding(get: { imagePath ?? "" }, set: { imagePath = $0 }))
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
                        .font(.caption)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                if let filename = store.saveImportedImage(data) { imagePath = filename }
                photoItem = nil
            }
        }
    }
}

struct MarketingContentEditorView: View {
    @EnvironmentObject private var store: MarketingContentStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Hero-Veranstaltung") {
                    MarketingImageField(imagePath: $store.content.hero.imagePath)
                    TextField("Datum & Uhrzeit", text: $store.content.hero.dateLabel)
                    TextField("Titel", text: $store.content.hero.title)
                    TextField("Veranstaltungsort", text: $store.content.hero.venue)
                }

                ForEach($store.content.modules) { $module in
                    Section {
                        TextField("Kategoriename", text: $module.title)

                        ForEach($module.events) { $event in
                            VStack(alignment: .leading, spacing: 8) {
                                MarketingImageField(imagePath: $event.imagePath)
                                TextField("Veranstaltungstitel", text: $event.title)
                                TextField("Datum, Uhrzeit · Ort", text: $event.subtitle)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in module.events.remove(atOffsets: offsets) }
                        .onMove { from, to in module.events.move(fromOffsets: from, toOffset: to) }

                        Button {
                            module.events.append(MarketingEventData(title: "Neue Veranstaltung", subtitle: "Datum, Uhrzeit · Ort"))
                        } label: {
                            Label("Veranstaltung hinzufügen", systemImage: "plus")
                        }
                    } header: {
                        HStack {
                            Text("Kategorie")
                            Spacer()
                            Button {
                                moveModule(module.id, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(!canMoveModule(module.id, by: -1))
                            Button {
                                moveModule(module.id, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(!canMoveModule(module.id, by: 1))
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.content.modules.removeAll { $0.id == module.id }
                        } label: {
                            Label("Kategorie löschen", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Button {
                        store.content.modules.append(MarketingModuleData(
                            title: "Neue Kategorie",
                            events: [MarketingEventData(title: "Neue Veranstaltung", subtitle: "Datum, Uhrzeit · Ort")]
                        ))
                    } label: {
                        Label("Kategorie hinzufügen", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    Button("Auf Standardinhalt zurücksetzen", role: .destructive) {
                        showsResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Startseite bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            .confirmationDialog(
                "Alle Kategorien, Veranstaltungen und Bilder werden auf die Standardwerte zurückgesetzt.",
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Zurücksetzen", role: .destructive) { store.resetToDefaults() }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    private func canMoveModule(_ id: UUID, by offset: Int) -> Bool {
        guard let index = store.content.modules.firstIndex(where: { $0.id == id }) else { return false }
        let target = index + offset
        return target >= 0 && target < store.content.modules.count
    }

    private func moveModule(_ id: UUID, by offset: Int) {
        guard let index = store.content.modules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target >= 0 && target < store.content.modules.count else { return }
        store.content.modules.swapAt(index, target)
    }
}
