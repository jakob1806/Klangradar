import SwiftUI

struct ProfileView: View {
    let usesPreviewData: Bool
    @ObservedObject var auth: AuthStore
    let userRepository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    @AppStorage("appearance") private var appearance = "system"
    @State private var showsLogin = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(KlangradarTheme.accent)
                        VStack(alignment: .leading) {
                            Text("Klangradar")
                                .font(.headline)
                            Text(usesPreviewData ? "Preview-Modus" : "Mit Supabase verbunden")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Account") {
                    accountContent
                }

                Section("Dein Klangradar") {
                    NavigationLink {
                        FavoriteEventsView(auth: auth, repository: userRepository, eventRepository: eventRepository, contentRepository: contentRepository)
                    } label: {
                        Label("Favoriten", systemImage: "heart")
                    }
                    NavigationLink {
                        UserEventListsView(
                            auth: auth,
                            repository: userRepository,
                            eventRepository: eventRepository,
                            contentRepository: contentRepository
                        )
                    } label: {
                        Label("Meine Listen", systemImage: "rectangle.stack")
                    }
                    NavigationLink {
                        InterestsView(auth: auth, repository: userRepository)
                    } label: {
                        Label("Interessen", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        NotificationSettingsView(auth: auth, repository: userRepository)
                    } label: {
                        Label("Benachrichtigungen", systemImage: "bell")
                    }
                }

                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Hell").tag("light")
                        Text("Dunkel").tag("dark")
                    }
                }

                Section("Über Klangradar") {
                    Link("Datenschutz", destination: URL(string: "https://klangradar.app/datenschutz")!)
                    Link("Impressum", destination: URL(string: "https://klangradar.app/impressum")!)
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showsLogin) {
                EmailCodeLoginView(auth: auth)
            }
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        switch auth.state {
        case .unavailable:
            Label("Im Preview-Modus nicht verfügbar", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Sitzung wird vorbereitet …")
        case .anonymous:
            Button("Mit E-Mail anmelden", systemImage: "envelope") {
                showsLogin = true
            }
        case let .authenticated(session):
            LabeledContent("Angemeldet als", value: session.user.email ?? "Klangradar Account")
            Button("Abmelden", role: .destructive) {
                Task { try? await auth.signOut() }
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Erneut versuchen") {
                Task { await auth.bootstrap() }
            }
        }
    }
}

private struct EmailCodeLoginView: View {
    @ObservedObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var didSendCode = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-Mail-Adresse", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    if didSendCode {
                        TextField("Bestätigungscode", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text("Klangradar sendet einen einmaligen Anmeldecode. Ein Passwort ist nicht notwendig.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(didSendCode ? "Code bestätigen" : "Code senden") {
                        Task { await submit() }
                    }
                    .disabled(
                        isWorking
                            || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (didSendCode && code.isEmpty)
                    )
                }
            }
            .navigationTitle("Anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            if didSendCode {
                try await auth.verifyEmailCode(code, email: email)
                dismiss()
            } else {
                try await auth.sendEmailCode(to: email)
                didSendCode = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FavoriteEventsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var events: [ConcertEvent] = []

    var body: some View {
        List(events) { event in NavigationLink(value: event) { Label(event.title, systemImage: "heart.fill") } }
            .overlay { if events.isEmpty { ContentUnavailableView("Noch keine Favoriten", systemImage: "heart", description: Text("Markierte Veranstaltungen erscheinen hier.")) } }
            .navigationTitle("Favoriten")
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: contentRepository) }
            .task {
                guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
                events = (try? await repository.favoriteEvents(userID: id, token: token)) ?? []
            }
    }
}

private struct UserEventListsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    @State private var lists: [UserEventList] = []
    @State private var showsCreate = false
    @State private var newName = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if auth.userID == nil {
                ContentUnavailableView(
                    "Anmeldung erforderlich",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Melde dich im Profil an, um persönliche Konzertlisten zu erstellen und zu synchronisieren.")
                )
            } else if isLoading {
                ProgressView("Listen werden geladen …")
            } else if lists.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Listen", systemImage: "rectangle.stack")
                } description: {
                    Text("Erstelle eine Liste und füge anschließend beliebige kommende Konzerte hinzu.")
                } actions: {
                    Button("Neue Liste") { showsCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(lists) { list in
                        NavigationLink {
                            UserEventListDetailView(
                                initialList: list,
                                auth: auth,
                                repository: repository,
                                eventRepository: eventRepository,
                                contentRepository: contentRepository
                            )
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "music.note.list")
                                    .font(.title3)
                                    .foregroundStyle(KlangradarTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(list.name).font(.headline)
                                    Text("\(list.events.count) \(list.events.count == 1 ? "Konzert" : "Konzerte")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Meine Listen")
        .toolbar {
            if auth.userID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Neue Liste", systemImage: "plus") { showsCreate = true }
                }
            }
        }
        .alert("Neue Konzertliste", isPresented: $showsCreate) {
            TextField("Name der Liste", text: $newName)
            Button("Abbrechen", role: .cancel) { newName = "" }
            Button("Erstellen") { Task { await create() } }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Du kannst den Namen später jederzeit ändern.")
        }
        .alert("Listen konnten nicht aktualisiert werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task { await load() }
        .onAppear { if !isLoading { Task { await load() } } }
    }

    private func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            isLoading = false
            return
        }
        do {
            lists = try await repository.eventLists(userID: userID, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        do {
            if let list = try await repository.createEventList(name: newName, userID: userID, token: token) {
                lists.insert(list, at: 0)
            }
            newName = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private func delete(at offsets: IndexSet) {
        guard let repository, let token = auth.accessToken else { return }
        let deleted = offsets.map { lists[$0] }
        lists.remove(atOffsets: offsets)
        Task {
            do {
                for list in deleted { try await repository.deleteEventList(id: list.id, token: token) }
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }
}

private struct UserEventListDetailView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var list: UserEventList
    @State private var showsPicker = false
    @State private var showsRename = false
    @State private var editedName: String

    init(
        initialList: UserEventList,
        auth: AuthStore,
        repository: UserRepository?,
        eventRepository: any EventRepository,
        contentRepository: any ContentRepository
    ) {
        _list = State(initialValue: initialList)
        _editedName = State(initialValue: initialList.name)
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
        self.contentRepository = contentRepository
    }

    var body: some View {
        Group {
            if list.events.isEmpty {
                ContentUnavailableView {
                    Label("Liste ist leer", systemImage: "music.note.list")
                } description: {
                    Text("Wähle Konzerte aus dem gesamten kommenden Programm aus.")
                } actions: {
                    Button("Konzerte auswählen") { showsPicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(list.events) { event in
                        NavigationLink(value: event) { UserListEventRow(event: event) }
                            .swipeActions {
                                Button("Entfernen", role: .destructive) { Task { await remove(event) } }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ConcertEvent.self) {
            EventDetailView(event: $0, repository: eventRepository, contentRepository: contentRepository)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Konzerte auswählen", systemImage: "plus") { showsPicker = true }
                Button("Umbenennen", systemImage: "pencil") {
                    editedName = list.name
                    showsRename = true
                }
            }
        }
        .sheet(isPresented: $showsPicker, onDismiss: { Task { await reload() } }) {
            EventListPicker(
                list: list,
                auth: auth,
                repository: repository,
                eventRepository: eventRepository
            )
        }
        .alert("Liste umbenennen", isPresented: $showsRename) {
            TextField("Name", text: $editedName)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") { Task { await rename() } }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func reload() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        if let updated = try? await repository.eventLists(userID: userID, token: token).first(where: { $0.id == list.id }) {
            list = updated
            editedName = updated.name
        }
    }

    private func rename() async {
        guard let repository, let token = auth.accessToken else { return }
        try? await repository.renameEventList(id: list.id, name: editedName, token: token)
        await reload()
    }

    private func remove(_ event: ConcertEvent) async {
        guard let repository, let token = auth.accessToken else { return }
        let previous = Set(list.events.map(\.id))
        try? await repository.replaceEvents(in: list.id, selected: previous.subtracting([event.id]), previous: previous, token: token)
        await reload()
    }
}

private struct EventListPicker: View {
    let list: UserEventList
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    @Environment(\.dismiss) private var dismiss
    @State private var events: [ConcertEvent] = []
    @State private var selected: Set<UUID>
    @State private var searchText = ""
    @State private var isSaving = false

    init(list: UserEventList, auth: AuthStore, repository: UserRepository?, eventRepository: any EventRepository) {
        self.list = list
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
        _selected = State(initialValue: Set(list.events.map(\.id)))
    }

    private var filtered: [ConcertEvent] {
        searchText.isEmpty ? events : events.filter {
            $0.title.localizedStandardContains(searchText) || $0.venueName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { event in
                Button { toggle(event.id) } label: {
                    HStack(spacing: 12) {
                        EventArtwork(event: event)
                            .frame(width: 64, height: 54)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: selected.contains(event.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(event.id) ? KlangradarTheme.accent : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay { if events.isEmpty { ProgressView("Konzerte werden geladen …") } }
            .navigationTitle("Konzerte auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Titel oder Ort")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert …" : "Fertig") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .task {
                let loaded = (try? await eventRepository.allUpcomingEvents()) ?? []
                events = (try? await eventRepository.enrichingImages(in: loaded)) ?? loaded
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func save() async {
        guard let repository, let token = auth.accessToken else { return }
        isSaving = true
        let previous = Set(list.events.map(\.id))
        try? await repository.replaceEvents(in: list.id, selected: selected, previous: previous, token: token)
        isSaving = false
        dismiss()
    }
}

private struct UserListEventRow: View {
    let event: ConcertEvent

    var body: some View {
        HStack(spacing: 12) {
            EventArtwork(event: event)
                .frame(width: 78, height: 64)
                .clipped()
                .clipShape(.rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline).lineLimit(2)
                Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct InterestsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var category: InterestCategory = .genre
    @State private var options: [InterestOption] = []
    @State private var selected: Set<String> = []
    @State private var searchText = ""

    private var filteredOptions: [InterestOption] {
        searchText.isEmpty ? options : options.filter { $0.label.localizedStandardContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(InterestCategory.allCases, id: \.self) { item in
                            Button { category = item } label: {
                                Label(item.title, systemImage: item.systemImage)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(category == item ? KlangradarTheme.accent : Color.secondary.opacity(0.12), in: .capsule)
                                    .foregroundStyle(category == item ? .white : .primary)
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            Section("\(category.title) · \(selected.count) ausgewählt") {
                ForEach(filteredOptions) { option in
                    Button { toggle(option.id) } label: {
                        HStack { Text(option.label).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(option.id) ? KlangradarTheme.accent : .secondary) }
                    }
                }
            }
        }
        .navigationTitle("Interessen")
        .searchable(text: $searchText, prompt: "\(category.title) durchsuchen")
        .task(id: category) { searchText = ""; await load() }
    }

    private func load() async {
        guard let repository else { return }
        options = (try? await repository.interestOptions(category)) ?? []
        guard let id = auth.userID, let token = auth.accessToken else { return }
        selected = (try? await repository.selectedInterests(category, userID: id, token: token)) ?? []
    }

    private func toggle(_ id: String) {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        let newValue = !selected.contains(id)
        if newValue { selected.insert(id) } else { selected.remove(id) }
        Task { try? await repository.setInterest(category, id: id, selected: newValue, userID: userID, token: token) }
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var preferences = NotificationPreferences()

    var body: some View {
        Form {
            Toggle("Neue passende Veranstaltungen", isOn: binding(\.newMatchingEvents, "new_matching_events"))
            Toggle("Preisänderungen", isOn: binding(\.priceChanges, "price_changes"))
            Toggle("Fast ausverkauft", isOn: binding(\.almostSoldOut, "almost_sold_out"))
            Toggle("Erinnerung am Vortag", isOn: binding(\.reminderDayBefore, "reminder_day_before"))
            // Deckt jetzt auch gefolgte Personen/Orte ab (siehe
            // notify-followed-entity-events), die Datenbankspalte heißt
            // aus historischen Gründen weiter "followed_ensemble_new_event".
            Toggle("Neue Termine gefolgter Personen, Ensembles & Orte", isOn: binding(\.followedEnsembleNewEvent, "followed_ensemble_new_event"))
        }
        .navigationTitle("Benachrichtigungen")
        .task {
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            preferences = (try? await repository.preferences(userID: id, token: token)) ?? NotificationPreferences()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>, _ column: String) -> Binding<Bool> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in
            preferences[keyPath: keyPath] = value
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            Task { try? await repository.setPreference(userID: id, token: token, column: column, value: value) }
        })
    }
}
