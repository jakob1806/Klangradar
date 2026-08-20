import SwiftUI

/// Punkt 16, "Schnellkorrektur-Modus": im Gegensatz zum vollen Event-Editor
/// (EditorialEventEditorView, der alle Programm-/Mitwirkenden-/Preis-Felder
/// zeigt) hier bewusst NUR die auf einem Konzertbesuch wirklich dringenden
/// Basisfelder (Titel, Untertitel, Termin, Venue, Bild) — mit "Speichern &
/// weiter" springt der Fokus direkt zum nächsten Event, ohne jedes Mal aus
/// der Liste heraus und wieder hinein navigieren zu müssen. Nutzt dieselbe
/// updateBasics()-Funktion wie EditorialEventEditorView.basicSection, die im
/// Repository schon als "native_editor_quick_update" protokolliert wird.
struct EditorialQuickFixView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository

    @State private var events: [EditorialEvent] = []
    @State private var venues: [EditorialOption] = []
    @State private var index = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Editierbarer Zustand des aktuell angezeigten Events.
    @State private var title = ""
    @State private var subtitle = ""
    @State private var startDate = Date()
    @State private var venueID: UUID?
    @State private var imageURL = ""
    @State private var isSaving = false
    @State private var skippedCount = 0
    @State private var savedCount = 0

    var body: some View {
        ZStack {
            EditorialBackground()
            if isLoading {
                ProgressView("Veranstaltungen werden geladen …").tint(KlangradarTheme.accent)
            } else if events.isEmpty {
                ContentUnavailableView("Keine Veranstaltungen", systemImage: "checkmark.circle", description: Text("Nichts zu korrigieren."))
            } else if index >= events.count {
                doneView
            } else {
                Form {
                    Section {
                        EditorialModeBanner(compact: true)
                    }
                    Section {
                        TextField("Titel", text: $title)
                        TextField("Untertitel", text: $subtitle)
                        DatePicker("Tag und Uhrzeit", selection: $startDate).datePickerStyle(.compact).tint(KlangradarTheme.accent)
                        Picker("Veranstaltungsort", selection: $venueID) {
                            ForEach(venues) { Text($0.title).tag(Optional($0.id)) }
                        }.tint(KlangradarTheme.accent)
                        TextField("Bild-URL", text: $imageURL, axis: .vertical)
                            .textInputAutocapitalization(.never).keyboardType(.URL)
                    } header: {
                        Text(events[index].venueName)
                    } footer: {
                        Text("Nur die Basisfelder — für Programm, Mitwirkende, Preise etc. das Event im Dashboard vollständig öffnen.")
                    }
                }
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) { controls }
            }
        }
        .navigationTitle("Schnellkorrektur")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .alert("Nicht gespeichert", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await load() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(index), total: Double(max(events.count, 1)))
                .tint(KlangradarTheme.accent)
            HStack {
                Text("\(index + 1) von \(events.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(savedCount) gespeichert · \(skippedCount) übersprungen").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Überspringen") { skip() }
                    .buttonStyle(.bordered)
                Button {
                    Task { await saveAndAdvance() }
                } label: {
                    Label("Speichern & weiter", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
                .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay { if isSaving { ProgressView() } }
    }

    private var doneView: some View {
        ContentUnavailableView {
            Label("Durchgang abgeschlossen", systemImage: "checkmark.seal.fill")
        } description: {
            Text("\(savedCount) gespeichert, \(skippedCount) übersprungen.")
        } actions: {
            Button("Von vorn beginnen") { index = 0; savedCount = 0; skippedCount = 0; loadFields() }
                .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
        }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; isLoading = false; return }
        isLoading = true; defer { isLoading = false }
        do {
            async let loadedEvents = repository.events(search: "", token: token)
            async let loadedVenues = repository.venues(token: token)
            // Bevorstehende zuerst — vor Ort korrigiert man i.d.R. das
            // gerade laufende oder nächste Konzert, nicht ein vergangenes.
            events = try await loadedEvents.sorted { $0.startDate < $1.startDate }
            venues = try await loadedVenues
            loadFields()
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadFields() {
        guard index < events.count else { return }
        let event = events[index]
        title = event.title
        subtitle = event.subtitle ?? ""
        startDate = event.startDate
        venueID = event.venueID
        imageURL = event.imageURL ?? ""
    }

    private func skip() {
        skippedCount += 1
        index += 1
        loadFields()
    }

    @MainActor private func saveAndAdvance() async {
        guard let token = auth.accessToken, let actor = auth.userID, let venueID, index < events.count else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await repository.updateBasics(
                event: events[index], title: title, subtitle: subtitle, startDate: startDate,
                venueID: venueID, imageURL: imageURL, actor: actor, token: token
            )
            savedCount += 1
            index += 1
            loadFields()
        } catch { errorMessage = error.localizedDescription }
    }
}
