import SwiftUI
import UIKit

struct ProfileView: View {
    let usesPreviewData: Bool
    @ObservedObject var auth: AuthStore
    let userRepository: UserRepository?
    let editorialRepository: EditorialRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    @AppStorage("appearance") private var appearance = "system"
    @State private var showsLogin = false
    @State private var hasEditorialAccess = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileOverview(
                        auth: auth,
                        repository: userRepository,
                        usesPreviewData: usesPreviewData
                    )
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
                    NavigationLink {
                        HomeCategoryOrderView(userID: auth.userID)
                    } label: {
                        Label("Homepage anordnen", systemImage: "arrow.up.arrow.down")
                    }
                }

                if hasEditorialAccess, let editorialRepository {
                    Section {
                        NavigationLink {
                            EditorialDashboardView(auth: auth, repository: editorialRepository)
                        } label: {
                            Label("Redaktionsmodus", systemImage: "exclamationmark.shield.fill")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Redaktion")
                    } footer: {
                        Text("Schnellkorrekturen wirken sich sofort auf alle Klangradar-Oberflächen aus.")
                    }
                }

                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Hell").tag("light")
                        Text("Dunkel").tag("dark")
                    }
                    AccentColorSettingsView()
                }

                Section("Über Klangradar") {
                    Link("Datenschutz", destination: URL(string: "https://klangradar.app/datenschutz")!)
                    NavigationLink {
                        ImpressumView()
                    } label: {
                        Text("Impressum")
                    }
                }
            }
            .navigationTitle("Profil")
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(
                    event: event,
                    repository: eventRepository,
                    contentRepository: contentRepository
                )
            }
            .navigationDestination(for: EntityRoute.self) { route in
                EntityDetailView(route: route, repository: contentRepository)
            }
            .sheet(isPresented: $showsLogin) {
                PasswordLoginView(auth: auth)
            }
            .task(id: auth.accessToken) { await checkEditorialAccess() }
        }
    }

    @MainActor
    private func checkEditorialAccess() async {
        guard let editorialRepository, let token = auth.accessToken else {
            hasEditorialAccess = false
            return
        }
        hasEditorialAccess = await editorialRepository.hasAccess(token: token)
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
            Button("Anmelden", systemImage: "envelope") {
                showsLogin = true
            }
        case let .authenticated(session):
            LabeledContent("Angemeldet als", value: session.user.email ?? "Klangradar Account")
            if BiometricAuth.availableBiometryKind != .none {
                Toggle(
                    BiometricAuth.availableBiometryKind == .faceID ? "Face ID zum Schutz nutzen" : "Touch ID zum Schutz nutzen",
                    isOn: Binding(
                        get: { BiometricAuth.isEnabled },
                        set: { UserDefaults.standard.set($0, forKey: BiometricAuth.enabledStorageKey) }
                    )
                )
            }
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

private struct AccentColorSettingsView: View {
    private struct AccentOption: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    private static let suggestions: [AccentOption] = [
        .init(name: "Klangradar Blau", hex: "#146194"),
        .init(name: "Indigo", hex: "#5856D6"),
        .init(name: "Violett", hex: "#AF52DE"),
        .init(name: "Pink", hex: "#D94F70"),
        .init(name: "Orange", hex: "#D96B2B"),
        .init(name: "Grün", hex: "#248A5B"),
        .init(name: "Türkis", hex: "#008C95")
    ]

    @AppStorage(KlangradarTheme.accentStorageKey) private var storedHex = KlangradarTheme.defaultAccentHex
    @State private var draftHex: String
    @FocusState private var hexFieldFocused: Bool

    init() {
        let current = UserDefaults.standard.string(forKey: KlangradarTheme.accentStorageKey)
            ?? KlangradarTheme.defaultAccentHex
        _draftHex = State(initialValue: current)
    }

    private var normalizedDraft: String? { KlangradarTheme.normalizedHex(draftHex) }
    private var normalizedStored: String {
        KlangradarTheme.normalizedHex(storedHex) ?? KlangradarTheme.defaultAccentHex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Akzentfarbe", systemImage: "paintpalette.fill")
                Spacer()
                Circle()
                    .fill(KlangradarTheme.color(hex: normalizedStored) ?? KlangradarTheme.accent)
                    .frame(width: 22, height: 22)
                    .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 2) }
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 13) {
                    ForEach(Self.suggestions) { option in
                        Button {
                            apply(option.hex)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(KlangradarTheme.color(hex: option.hex) ?? .clear)
                                        .frame(width: 38, height: 38)
                                    if normalizedStored == option.hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay {
                                    Circle().stroke(
                                        normalizedStored == option.hex ? Color.primary.opacity(0.25) : Color.clear,
                                        lineWidth: 3
                                    ).padding(-3)
                                }
                                Text(option.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.name)
                        .accessibilityValue(normalizedStored == option.hex ? "Ausgewählt" : "")
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
            }

            ColorPicker(
                "Farbe frei wählen",
                selection: Binding(
                    get: { KlangradarTheme.color(hex: normalizedStored) ?? KlangradarTheme.accent },
                    set: { color in
                        guard let hex = KlangradarTheme.hex(color: color) else { return }
                        apply(hex)
                    }
                ),
                supportsOpacity: false
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Eigener Hex-Code").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("#146194", text: $draftHex)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .focused($hexFieldFocused)
                        .onSubmit { commitDraft() }
                    Button("Übernehmen") { commitDraft() }
                        .font(.subheadline.weight(.semibold))
                        .disabled(normalizedDraft == nil || normalizedDraft == normalizedStored)
                }
                if !draftHex.isEmpty, normalizedDraft == nil {
                    Text("Bitte sechs Hex-Zeichen eingeben, z. B. #146194.")
                        .font(.caption2).foregroundStyle(.red)
                } else {
                    Text("Die Farbe gilt sofort für Navigation, Buttons und Auswahlzustände.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: storedHex) { _, newValue in
            guard !hexFieldFocused else { return }
            draftHex = KlangradarTheme.normalizedHex(newValue) ?? KlangradarTheme.defaultAccentHex
        }
    }

    private func commitDraft() {
        guard let normalizedDraft else { return }
        apply(normalizedDraft)
        hexFieldFocused = false
    }

    private func apply(_ hex: String) {
        guard let normalized = KlangradarTheme.normalizedHex(hex) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            storedHex = normalized
            draftHex = normalized
        }
    }
}

private struct ProfileOverview: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let usesPreviewData: Bool
    @State private var profile: KlangradarUserProfile?

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatarEditor(auth: auth, repository: repository)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.headline)
                Text(accountLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if auth.userID != nil {
                NavigationLink {
                    AccountProfileEditView(auth: auth, repository: repository)
                } label: {
                    Text("Bearbeiten")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 6)
        .task(id: auth.userID) { await load() }
        .onAppear { Task { await load() } }
    }

    private var displayName: String {
        if let name = profile?.displayName, !name.isEmpty { return name }
        if let email = auth.session?.user.email { return email.split(separator: "@").first.map(String.init) ?? email }
        return usesPreviewData ? "Preview-Profil" : "Dein Profil"
    }

    private var accountLine: String {
        auth.session?.user.email ?? (usesPreviewData ? "Preview-Modus" : "Noch nicht angemeldet")
    }

    private func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            profile = nil
            return
        }
        profile = try? await repository.profile(userID: userID, token: token)
    }
}

private struct AccountProfileEditView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Persönliche Angaben") {
                TextField("Name", text: $displayName)
                    .textContentType(.name)

                Toggle("Geburtstag hinterlegen", isOn: $hasBirthDate.animation())
                if hasBirthDate {
                    DatePicker(
                        "Geburtstag",
                        selection: $birthDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                }
            }

            Section("E-Mail-Adresse") {
                TextField("E-Mail-Adresse", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Text("Nach einer Änderung sendet Supabase gegebenenfalls eine Bestätigung an die bisherige und die neue Adresse.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Neues Passwort") {
                SecureField("Mindestens 8 Zeichen", text: $password)
                    .textContentType(.newPassword)
                SecureField("Passwort wiederholen", text: $passwordConfirmation)
                    .textContentType(.newPassword)
                Text("Leer lassen, wenn das Passwort nicht geändert werden soll.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .disabled(isLoading || isSaving)
        .overlay { if isLoading || isSaving { ProgressView() } }
        .navigationTitle("Profil bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { Task { await save() } }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        email = auth.session?.user.email ?? ""
        guard let repository, let userID = auth.userID, let token = auth.accessToken,
              let profile = try? await repository.profile(userID: userID, token: token) else { return }
        displayName = profile.displayName
        if let date = profile.birthDate {
            birthDate = date
            hasBirthDate = true
        }
    }

    private func save() async {
        errorMessage = nil
        message = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@") else {
            errorMessage = "Bitte gib eine gültige E-Mail-Adresse ein."
            return
        }
        if !password.isEmpty {
            guard password.count >= 8 else {
                errorMessage = "Das neue Passwort muss mindestens 8 Zeichen lang sein."
                return
            }
            guard password == passwordConfirmation else {
                errorMessage = "Die eingegebenen Passwörter stimmen nicht überein."
                return
            }
        }

        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.updateProfile(
                displayName: displayName,
                birthDate: hasBirthDate ? birthDate : nil,
                userID: userID,
                token: token
            )
            if cleanEmail != auth.session?.user.email?.lowercased() {
                try await auth.updateEmail(cleanEmail)
            }
            if !password.isEmpty {
                try await auth.updatePassword(password)
                password = ""
                passwordConfirmation = ""
            }
            message = "Deine Änderungen wurden gespeichert."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct HomeCategoryOrderView: View {
    let userID: UUID?
    @State private var categories: [HomeRecommendationCategory]

    init(userID: UUID?) {
        self.userID = userID
        _categories = State(initialValue: HomeCategoryPreferences.order(for: userID))
    }

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Label(category.title, systemImage: category.symbol)
                }
                .onMove(perform: move)
            } header: {
                Text("Reihenfolge")
            } footer: {
                Text("Halte eine Kategorie am Griff rechts fest und verschiebe sie nach oben oder unten. Die Titelveranstaltung bleibt immer an erster Stelle.")
            }

            Section {
                Button("Standardreihenfolge wiederherstellen", systemImage: "arrow.counterclockwise") {
                    HomeCategoryPreferences.reset(for: userID)
                    categories = HomeRecommendationCategory.defaultOrder
                }
            }
        }
        .navigationTitle("Homepage anordnen")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .onAppear {
            categories = HomeCategoryPreferences.order(for: userID)
        }
        .onDisappear {
            // Zusätzlich zum sofortigen Speichern nach jedem Drag: schützt
            // vor einem SwiftUI-Neuaufbau während der Move-Animation.
            HomeCategoryPreferences.save(categories, for: userID)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        HomeCategoryPreferences.save(categories, for: userID)
    }
}


private struct FavoriteEventsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var events: [ConcertEvent] = []

    var body: some View {
        List(events) { event in
            NavigationLink {
                EventDetailView(
                    event: event,
                    repository: eventRepository,
                    contentRepository: contentRepository
                )
            } label: {
                FavoriteEventRow(event: event)
            }
        }
            .overlay { if events.isEmpty { ContentUnavailableView("Noch keine Favoriten", systemImage: "heart", description: Text("Markierte Veranstaltungen erscheinen hier.")) } }
            .navigationTitle("Favoriten")
            .task {
                guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
                let loaded = (try? await repository.favoriteEvents(userID: id, token: token)) ?? []
                events = (try? await eventRepository.enrichingImages(in: loaded)) ?? loaded
            }
    }
}

private struct FavoriteEventRow: View {
    let event: ConcertEvent

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: event.primaryImageURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    placeholder.overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(event.dateLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(KlangradarTheme.accent.opacity(0.1))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(KlangradarTheme.accent)
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

