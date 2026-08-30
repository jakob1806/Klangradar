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
    enum Surface { case home, search }

    @EnvironmentObject private var store: MarketingContentStore
    @Environment(\.dismiss) private var dismiss
    let surface: Surface
    let availableEvents: [ConcertEvent]
    let onFinished: () -> Void
    @State private var showsResetConfirmation = false
    @State private var showsHeroPicker = false

    var body: some View {
        NavigationStack {
            List {
                if surface == .home {
                    Section("Hero-Veranstaltung") {
                        Button {
                            showsHeroPicker = true
                        } label: {
                            Label(
                                store.content.hero.sourceEventID == nil ? "Echtes Event auswählen" : "Verknüpftes Event ändern",
                                systemImage: "calendar.badge.plus"
                            )
                        }
                        MarketingImageField(imagePath: $store.content.hero.imagePath)
                        TextField("Datum & Uhrzeit", text: $store.content.hero.dateLabel)
                        TextField("Titel", text: $store.content.hero.title)
                        TextField("Veranstaltungsort", text: $store.content.hero.venue)
                    }

                    ForEach($store.content.modules) { $module in
                        Section {
                            TextField("Kategoriename", text: $module.title)

                            ForEach($module.events) { $event in
                                MarketingEditableEventFields(event: $event, availableEvents: availableEvents)
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
                                Button { moveModule(module.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(!canMoveModule(module.id, by: -1))
                                Button { moveModule(module.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(!canMoveModule(module.id, by: 1))
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.content.modules.removeAll { $0.id == module.id } } label: {
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
                } else {
                    Section("Suche") {
                        TextField("Überschrift", text: $store.content.search.headline)
                    }
                    Section("Angezeigte Veranstaltungen") {
                        ForEach($store.content.search.events) { $event in
                            MarketingEditableEventFields(event: $event, availableEvents: availableEvents)
                        }
                        .onDelete { offsets in store.content.search.events.remove(atOffsets: offsets) }
                        .onMove { from, to in store.content.search.events.move(fromOffsets: from, toOffset: to) }
                        Button {
                            store.content.search.events.append(MarketingEventData(title: "Neue Veranstaltung", subtitle: "Datum, Uhrzeit · Ort"))
                        } label: {
                            Label("Veranstaltung hinzufügen", systemImage: "plus")
                        }
                    }
                }

                Section {
                    Button("Auf Standardinhalt zurücksetzen", role: .destructive) {
                        showsResetConfirmation = true
                    }
                }
            }
            .navigationTitle(surface == .home ? "Startseite bearbeiten" : "Suche bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        onFinished()
                        dismiss()
                    }
                }
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
            .sheet(isPresented: $showsHeroPicker) {
                MarketingEventPicker(events: availableEvents) { event in
                    store.content.hero.sourceEventID = event.id
                    store.content.hero.imagePath = event.primaryImageURL?.absoluteString
                    store.content.hero.dateLabel = marketingHeroDateLabel(for: event)
                    store.content.hero.title = event.title
                    store.content.hero.venue = event.venueName
                }
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

/// Ein echtes Event füllt die Karte vor, ohne die gestalterische Freiheit zu
/// nehmen: Bild, Titel und Unterzeile können anschließend weiter angepasst
/// werden. Der Bezug sorgt zugleich dafür, dass ein Tippen in der Aufnahme
/// zur echten Event-Detailansicht führt.
private struct MarketingEditableEventFields: View {
    @Binding var event: MarketingEventData
    let availableEvents: [ConcertEvent]
    @State private var showsPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showsPicker = true
            } label: {
                Label(
                    event.sourceEventID == nil ? "Echtes Event auswählen" : "Verknüpftes Event ändern",
                    systemImage: "calendar.badge.plus"
                )
                .font(.subheadline.weight(.medium))
            }
            MarketingImageField(imagePath: $event.imagePath)
            TextField("Veranstaltungstitel", text: $event.title)
            TextField("Datum, Uhrzeit · Ort", text: $event.subtitle)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showsPicker) {
            MarketingEventPicker(events: availableEvents) { selected in
                event.sourceEventID = selected.id
                event.imagePath = selected.primaryImageURL?.absoluteString
                event.title = selected.title
                event.subtitle = selected.dateLine
            }
        }
    }
}

private struct MarketingEventPicker: View {
    @Environment(\.dismiss) private var dismiss
    let events: [ConcertEvent]
    let onSelect: (ConcertEvent) -> Void
    @State private var query = ""

    private var filteredEvents: [ConcertEvent] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return events }
        return events.filter {
            $0.title.localizedCaseInsensitiveContains(normalized)
                || $0.venueName.localizedCaseInsensitiveContains(normalized)
                || $0.dateLine.localizedCaseInsensitiveContains(normalized)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView(
                        "Keine kommenden Events geladen",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Bitte kurz warten oder die Vorschau erneut öffnen.")
                    )
                } else if filteredEvents.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filteredEvents) { event in
                        Button {
                            onSelect(event)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: event.primaryImageURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.secondary.opacity(0.14)
                                        .overlay { Image(systemName: "music.note") }
                                }
                                .frame(width: 54, height: 54)
                                .clipShape(.rect(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).foregroundStyle(.primary).lineLimit(2)
                                    Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Event auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Titel, Ort oder Termin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

private func marketingHeroDateLabel(for event: ConcertEvent) -> String {
    guard let date = event.startDate else { return "TERMIN FOLGT" }
    return KlangradarDateTime.string(date, format: "EEE., d. MMM · HH:mm").uppercased()
}
