import SwiftUI

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

/// Veranstaltungs-Editor (Schnellkorrektur der Basisdaten, weitere Angaben,
/// Mitwirkende, Programm) — vom Dashboard aus erreichbar, daher `internal`
/// statt `private`.
struct EditorialEventEditorView: View {
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
    @State private var showsProgramScan = false
    @State private var showsCreateVenue = false
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
        Form {
            Section { EditorialModeBanner(compact: true) }
            basicSection
            detailsSection
            participantsSection
            programSection
            Section { EditorialAIAssistantView(auth: auth, repository: repository, entityType: "event", entityID: initialEvent.id) }
            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(EditorialBackground())
        .disabled(isLoading || isSaving || isDeleting)
        .overlay { if isLoading || isSaving || isDeleting { ProgressView().tint(KlangradarTheme.accent) } }
        .navigationTitle("Veranstaltung bearbeiten")
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
        .fullScreenCover(isPresented: $showsProgramScan) {
            EditorialProgramScanView(
                auth: auth, repository: repository, event: detail?.event ?? initialEvent,
                existingWorkCount: detail?.works.count ?? 0
            ) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showsCreateVenue) {
            EditorialCreateVenueView(auth: auth, repository: repository) { option in
                venues.append(option)
                venueID = option.id
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

    private var basicSection: some View {
        Section {
            TextField("Titel", text: $title)
            TextField("Untertitel", text: $subtitle)
            DatePicker("Tag und Uhrzeit", selection: $startDate)
                .datePickerStyle(.compact).tint(KlangradarTheme.accent)
            Picker("Veranstaltungsort", selection: $venueID) {
                ForEach(venues) { Text($0.title).tag($0.id) }
            }.tint(KlangradarTheme.accent)
            // Punkt 20, "Event-Zuweisung": neue Venue anlegen und direkt für
            // dieses Event übernehmen, ohne den Editor verlassen zu müssen.
            Button("Neue Venue anlegen", systemImage: "plus.circle") { showsCreateVenue = true }
                .font(.caption)
            TextField("Bild-URL", text: $imageURL, axis: .vertical)
                .textInputAutocapitalization(.never).keyboardType(.URL)
            EditorialGalleryEditor(auth: auth, repository: repository, originType: "event", originID: initialEvent.id) { primaryURL in
                imageURL = primaryURL ?? ""
            }
            Button { Task { await saveBasics() } } label: {
                Label(message ?? "Basisdaten speichern", systemImage: message == nil ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent).disabled(isSaving)
        } header: {
            Text("Basisdaten")
        } footer: {
            Text("Wird direkt in Supabase gespeichert und ist damit im Admin-Portal, in der Web-/Vercel-Ausgabe sowie in Flutter und Native verfügbar.")
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
    /// (basicSection) — eigene Section mit eigenem Speichern-Button, damit die
    /// bestehende Schnellkorrektur unverändert nutzbar bleibt.
    private var detailsSection: some View {
        Section("Weitere Angaben") {
            TextField("Beschreibung", text: $descriptionDe, axis: .vertical).lineLimit(3...8)
            TextField("Dauer (Minuten)", text: $durationMinutesText).keyboardType(.numberPad)
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

            Button { showsGenrePicker = true } label: {
                LabeledContent("Genres", value: selectedGenreIDs.isEmpty ? "Auswählen" : "\(selectedGenreIDs.count) gewählt")
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
                .listRowSeparator(.hidden)
            }

            TextField("Preis von (€)", text: $priceMinText).keyboardType(.decimalPad)
            TextField("Preis bis (€)", text: $priceMaxText).keyboardType(.decimalPad)
            Toggle("Kostenlos", isOn: $isFree).tint(KlangradarTheme.accent)
            TextField("Ticket-Link", text: $ticketURL).textInputAutocapitalization(.never).keyboardType(.URL)

            Picker("Ticket-Status", selection: $remainingTicketsStatus) {
                ForEach(Self.TICKET_STATUS_OPTIONS, id: \.value) { Text($0.label).tag($0.value) }
            }.tint(KlangradarTheme.accent)

            TextField("Einlass", text: $doorsInfo)
            TextField("Altersbeschränkung", text: $ageRestriction)
            TextField("Ermäßigung", text: $discountInfo)
            TextField("Vorverkaufsgebühr", text: $presaleFeeInfo)

            Picker("Status", selection: $status) {
                ForEach(Self.STATUS_OPTIONS, id: \.value) { Text($0.label).tag($0.value) }
            }.tint(KlangradarTheme.accent)

            Button { Task { await saveDetails() } } label: {
                Label(detailsMessage ?? "Weitere Angaben speichern", systemImage: detailsMessage == nil ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent).disabled(isSavingDetails)
        }
    }

    private var participantsSection: some View {
        Section("Mitwirkende") {
            if detail?.participants.isEmpty != false { Text("Keine Mitwirkenden hinterlegt").foregroundStyle(.secondary) }
            ForEach(detail?.participants ?? []) { participant in
                HStack {
                    VStack(alignment: .leading) { Text(participant.name); if let role = participant.roleLabel { Text(role).font(.caption).foregroundStyle(KlangradarTheme.accent) } }
                    Spacer()
                    Button(role: .destructive) { Task { await remove(participant) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                }
            }
            Button("Person hinzufügen", systemImage: "person.badge.plus") { picker = .person }
            Button("Ensemble hinzufügen", systemImage: "person.3") { picker = .ensemble }
        }
    }

    private var programSection: some View {
        Section("Programm") {
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
                        VStack(alignment: .leading) {
                            Text(link.title)
                            if let composer = link.composer { Text(composer).font(.caption).foregroundStyle(KlangradarTheme.accent) }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) { Task { await remove(link) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                }
            }
            Button("Werk hinzufügen", systemImage: "plus") { picker = .work }
            // Punkt 18: statt Werke/Mitwirkende einzeln über den Picker
            // hinzuzufügen, ein ganzes Programmheft fotografieren und die
            // erkannten Zeilen in einem Rutsch zuordnen.
            Button("Programmheft scannen", systemImage: "camera.viewfinder") { showsProgramScan = true }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                Label("Veranstaltung löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text("Löscht den Eintrag dauerhaft aus allen Klangradar-Anwendungen.")
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
            RecentlyEditedStore.shared.record(kind: .event, id: initialEvent.id, title: title)
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
            RecentlyEditedStore.shared.record(kind: .event, id: initialEvent.id, title: title)
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
