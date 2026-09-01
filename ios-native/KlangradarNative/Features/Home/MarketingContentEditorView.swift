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

                    // Nutzerfeedback: "Verschieben der Kategorien ist noch zu
                    // schwer" — die Chevron-Tasten pro Sektion brauchten bei
                    // vielen Kategorien (jetzt alle echten Home-Reihen, siehe
                    // MarketingContentStore) viele Taps für eine weite
                    // Verschiebung. Jede Kategorie ist jetzt eine eigene
                    // Zeile mit echtem Drag-Griff (über "Bearbeiten" oben
                    // rechts einblendbar) statt eines aufgeklappten
                    // Formulars; Titel/Veranstaltungen werden beim Antippen
                    // in einem eigenen Bildschirm bearbeitet.
                    Section("Kategorien") {
                        ForEach($store.content.modules) { $module in
                            NavigationLink {
                                MarketingModuleEditorView(module: $module, availableEvents: availableEvents)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(module.title.isEmpty ? "Unbenannte Kategorie" : module.title)
                                    Text("\(module.events.count) Veranstaltung\(module.events.count == 1 ? "" : "en")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in store.content.modules.remove(atOffsets: offsets) }
                        .onMove { from, to in store.content.modules.move(fromOffsets: from, toOffset: to) }

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

}

/// Eigener Bildschirm für eine Kategorie -- Titel und ihre Veranstaltungen,
/// aus der Kategorienliste per Tap erreichbar (siehe deren
/// Nutzerfeedback-Kommentar). Events bleiben innerhalb der Kategorie per
/// Drag-Griff sortierbar.
private struct MarketingModuleEditorView: View {
    @Binding var module: MarketingModuleData
    let availableEvents: [ConcertEvent]

    var body: some View {
        Form {
            Section("Kategoriename") {
                TextField("Kategoriename", text: $module.title)
            }
            Section("Veranstaltungen") {
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
            }
        }
        .navigationTitle(module.title.isEmpty ? "Kategorie" : module.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
    }
}

/// Ein echtes Event füllt die Karte vor, ohne die gestalterische Freiheit zu
/// nehmen: Bild, Titel und Unterzeile können anschließend weiter angepasst
/// werden. Der Bezug sorgt zugleich dafür, dass ein Tippen in der Aufnahme
/// zur echten Event-Detailansicht führt.
struct MarketingEditableEventFields: View {
    @Binding var event: MarketingEventData
    let availableEvents: [ConcertEvent]
    @State private var showsPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Nutzerfeedback: ein Tap hier landete öfter versehentlich auf
            // "Aus Fotos wählen" direkt darunter -- beide saßen mit nur 8pt
            // Abstand in derselben Zeile, ohne eigene Tapfläche. Jetzt mehr
            // Abstand plus explizit begrenzte, nicht per Zufall
            // überlappende Tapfläche für den Button.
            Button {
                showsPicker = true
            } label: {
                Label(
                    event.sourceEventID == nil ? "Echtes Event auswählen" : "Verknüpftes Event ändern",
                    systemImage: "calendar.badge.plus"
                )
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            MarketingImageField(imagePath: $event.imagePath)
            TextField("Veranstaltungstitel", text: $event.title)
            TextField("Datum, Uhrzeit · Ort", text: $event.subtitle)
            // Nur auf der Entdecken-Kachel in der Suche sichtbar (siehe
            // MarketingSearchDiscoveryEventCard) -- auf den übrigen Karten
            // wirkungslos, bleibt aber überall editierbar, falls eine Karte
            // später dorthin verschoben wird.
            TextField("Kategorie-Label (z. B. KONZERT, OPER)", text: $event.categoryLabel)
                .textInputAutocapitalization(.characters)
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
    @EnvironmentObject private var cityStore: CityStore
    let events: [ConcertEvent]
    let onSelect: (ConcertEvent) -> Void
    @State private var query = ""
    // Nutzerfeedback: die Suche über alle Städte hinweg (~1.800 Events) war
    // spürbar laggy und ein Stadt-Filter fehlte ganz. Der Filter grenzt die
    // Kandidatenliste VOR der Textsuche ein -- startet mit der in Home/Suche
    // aktuell gewählten Stadt, da das meistens auch die Stadt ist, für die
    // gerade Screenshots vorbereitet werden.
    @State private var cityFilter: UUID?

    private var cityScopedEvents: [ConcertEvent] {
        guard let cityFilter else { return events }
        return events.filter { $0.venues?.cityId == cityFilter }
    }

    private var filteredEvents: [ConcertEvent] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return cityScopedEvents }
        return cityScopedEvents.filter {
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
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Alle Städte") { cityFilter = nil }
                        ForEach(cityStore.activeCities) { city in
                            Button(city.name) { cityFilter = city.id }
                        }
                    } label: {
                        Label(cityStore.activeCities.first { $0.id == cityFilter }?.name ?? "Alle Städte", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .onAppear {
                if cityFilter == nil { cityFilter = cityStore.selectedCity?.id }
            }
        }
    }
}

/// Nutzerfeedback: der Umweg über den Stift → großes Formular → richtige
/// Karte suchen war zu umständlich. Im Vorbereiten-Modus öffnet ein Tap auf
/// eine Karte direkt diesen kompakten Editor für genau diese eine
/// Veranstaltung — Home/Suche bleiben dabei sichtbar im Hintergrund.
struct MarketingQuickEditSheet: View {
    @Binding var event: MarketingEventData
    let availableEvents: [ConcertEvent]
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Diese Karte") {
                    MarketingEditableEventFields(event: $event, availableEvents: availableEvents)
                }
                if let onDelete {
                    Section {
                        Button("Karte entfernen", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Karte bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private func marketingHeroDateLabel(for event: ConcertEvent) -> String {
    guard let date = event.startDate else { return "TERMIN FOLGT" }
    return KlangradarDateTime.string(date, format: "EEE, d. MMM · HH:mm").uppercased()
}
