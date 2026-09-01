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
    @AppStorage(BiometricAuth.enabledStorageKey) private var biometricProtectionEnabled = false
    @EnvironmentObject private var cityStore: CityStore
    @State private var showsLogin = false
    @State private var hasEditorialAccess = false
    @State private var showsMarketingShell = false

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
                        PersonalConciergeView(auth: auth, repository: userRepository, eventRepository: eventRepository, contentRepository: contentRepository)
                    } label: {
                        Label("Assistent & Abendplaner", systemImage: "sparkles")
                    }
                    NavigationLink {
                        MyKlangradarHubView(auth: auth, repository: userRepository)
                    } label: {
                        Label("Mein Klangradar", systemImage: "person.crop.rectangle.stack")
                    }
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
                    // Nutzerwunsch: unter Profil öffnet die Stadtauswahl eine
                    // volle Seite (Push) statt eines Popups/Sheets — Home,
                    // Suche und Kalender nutzen weiterhin CityCompactMenu mit
                    // Sheet-Präsentation, siehe CitySwitcherView.
                    NavigationLink {
                        CitySwitcherView(cityStore: cityStore, embedsNavigationStack: false)
                    } label: {
                        HStack {
                            Label {
                                Text("Stadt")
                            } icon: {
                                Image(systemName: "building.2").foregroundStyle(KlangradarTheme.accent)
                            }
                            Spacer()
                            Text(cityStore.selectedCity?.name ?? "Alle Städte")
                                .foregroundStyle(.secondary)
                        }
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

                // Marketing-Aufnahmen gehören in eine auslieferbare App,
                // aber nicht in den öffentlichen Nutzerfluss. Der Zugang ist
                // deshalb an den schon bestehenden Redaktionszugang gebunden
                // statt an das DEBUG-Build-Flag. Ein einziger Einstieg statt
                // zwei getrennter Modi: startet sofort bearbeitbar (Stift
                // oben rechts in Home/Suche), „Fertig“ blendet Stift und X
                // aus und macht die Oberfläche aufnahmebereit; heraus kommt
                // man per Doppeltipp auf Home in der Tableiste.
                if hasEditorialAccess {
                    Section {
                        Button {
                            showsMarketingShell = true
                        } label: {
                            Label("Marketing-Screenshots", systemImage: "camera.viewfinder")
                        }
                    } header: {
                        Text("Marketing")
                    } footer: {
                        Text("Home und Suche bleiben zunächst bearbeitbar: Stift oben rechts wählt Inhalte, Texte und Bilder — auch echte Veranstaltungen statt Platzhaltern. Alles andere verhält sich wie die normale App. Mit „Fertig“ verschwinden Stift und X, und die Oberfläche ist aufnahmebereit. Heraus kommst du per Doppeltipp auf Home in der Tableiste.")
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
                PasswordLoginView(auth: auth, repository: userRepository)
            }
            .fullScreenCover(isPresented: $showsMarketingShell) {
                MarketingAppShellView(
                    auth: auth,
                    userRepository: userRepository,
                    editorialRepository: editorialRepository,
                    eventRepository: eventRepository,
                    contentRepository: contentRepository,
                    usesPreviewData: usesPreviewData
                )
            }
            .task(id: auth.accessToken) { await checkEditorialAccess() }
        }
    }

    @MainActor
    private func checkEditorialAccess() async {
        guard let editorialRepository, let token = auth.accessToken, let userID = auth.userID else {
            hasEditorialAccess = false
            return
        }
        let cacheKey = "editorialAccess.\(userID.uuidString.lowercased())"
        if UserDefaults.standard.bool(forKey: cacheKey) {
            hasEditorialAccess = true
        }
        // Beim Wiederherstellen der Sitzung kann der erste Rollencheck noch
        // mit einem gerade erneuerten Token kollidieren. Kurze Wiederholungen
        // verhindern, dass der Redaktionsmodus dadurch komplett verschwindet.
        for attempt in 0..<3 {
            if await editorialRepository.hasAccess(token: token) {
                hasEditorialAccess = true
                UserDefaults.standard.set(true, forKey: cacheKey)
                return
            }
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(450)) }
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
            Button("Anmelden", systemImage: "envelope") {
                showsLogin = true
            }
        case let .authenticated(session):
            LabeledContent("Angemeldet als", value: session.user.email ?? "Klangradar Account")
            if BiometricAuth.availableBiometryKind != .none {
                Toggle(
                    BiometricAuth.availableBiometryKind == .faceID ? "Face ID zum Schutz nutzen" : "Touch ID zum Schutz nutzen",
                    isOn: Binding(
                        get: { biometricProtectionEnabled },
                        set: { enabled in
                            if enabled {
                                Task {
                                    if (try? await BiometricAuth.authenticate(reason: "Biometrischen Schutz für Klangradar aktivieren")) == true {
                                        biometricProtectionEnabled = true
                                    }
                                }
                            } else {
                                biometricProtectionEnabled = false
                            }
                        }
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

private struct PersonalConciergeView: View {
    private struct Message: Identifiable { let id = UUID(); let text: String; let isUser: Bool }
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @EnvironmentObject private var favorites: FavoriteStore
    @State private var conversationID: UUID?
    @State private var messages: [Message] = [
        .init(text: "Erzähl mir, wie dein Abend aussehen soll. Ich suche nur echte Veranstaltungen aus Klangradar und merke mir Änderungen im Gespräch.", isUser: false)
    ]
    @State private var events: [PersonalConciergeEvent] = []
    @State private var places: [PersonalConciergePlace] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let prompts = ["Samstag romantisch, bis 50 €", "Heute spontan und unter 30 €", "Kammermusik, danach Restaurant", "U30-Angebote in München"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.count == 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(prompts, id: \.self) { prompt in
                                Button(prompt) { draft = prompt; Task { await send() } }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            } }
                        }
                    }
                    ForEach(messages) { message in
                        HStack {
                            if message.isUser { Spacer(minLength: 48) }
                            Text(message.text)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(message.isUser ? KlangradarTheme.accent : Color(uiColor: .secondarySystemGroupedBackground))
                                .foregroundStyle(message.isUser ? .white : .primary)
                                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                            if !message.isUser { Spacer(minLength: 48) }
                        }
                    }
                    ForEach(events) { event in conciergeEventCard(event) }
                    if !places.isEmpty {
                        Text("Danach in der Nähe").font(.title3.bold()).padding(.top, 4)
                        ForEach(places) { place in
                            if let url = place.mapsURL {
                                Link(destination: url) { placeRow(place) }
                            } else { placeRow(place) }
                        }
                    }
                    if isLoading { ProgressView("Ich suche in Klangradar …").frame(maxWidth: .infinity).padding() }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    TextField("Etwas günstiger, lieber früher …", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4).submitLabel(.send)
                        .onSubmit { Task { await send() } }
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title).symbolRenderingMode(.hierarchical)
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }.padding().background(.ultraThinMaterial)
            }
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
        }
        .navigationTitle("Klangradar Assistent").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ConcertEvent.self) { event in
            EventDetailView(event: event, repository: eventRepository, contentRepository: contentRepository)
        }
    }

    @ViewBuilder private func conciergeEventCard(_ event: PersonalConciergeEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: event.concertEvent) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.startDate.map { KlangradarDateTime.string($0, format: "EEE, d. MMM · HH:mm") } ?? "Termin folgt")
                        .font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                    Text(event.title).font(.headline).foregroundStyle(.primary)
                    Text(event.venueName).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !event.reasons.isEmpty {
                Text(event.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(favorites.ids.contains(event.id) ? "Gespeichert" : "Speichern", systemImage: favorites.ids.contains(event.id) ? "heart.fill" : "heart") {
                    Task { await favorites.toggle(event.id) }
                }.buttonStyle(.bordered)
                if let url = event.ticketURL { Link(destination: url) { Label("Tickets", systemImage: "ticket") }.buttonStyle(.borderedProminent) }
                ShareLink(item: "\(event.title) – \(event.venueName)") { Image(systemName: "square.and.arrow.up") }
            }
        }.padding(15).background(Color(uiColor: .secondarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 20, style: .continuous))
    }

    private func placeRow(_ place: PersonalConciergePlace) -> some View {
        HStack { Image(systemName: "fork.knife.circle.fill").font(.title2); VStack(alignment: .leading) {
            Text(place.name).font(.headline); Text([place.address, place.rating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }; Spacer(); Image(systemName: "arrow.up.right") }.padding(12).background(Color(uiColor: .secondarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 16))
    }

    @MainActor private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading, let repository, let token = auth.accessToken else {
            if auth.accessToken == nil { errorMessage = "Bitte melde dich an, damit ich Gesprächskontext und persönliche Empfehlungen sicher speichern kann." }
            return
        }
        draft = ""; errorMessage = nil; isLoading = true; messages.append(.init(text: text, isUser: true))
        defer { isLoading = false }
        do {
            let result = try await repository.askConcierge(message: text, conversationID: conversationID, token: token)
            conversationID = result.conversationID; events = result.events; places = result.places
            messages.append(.init(text: result.message, isUser: false))
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct MyKlangradarHubView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var stats: KlangradarStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Deine Klassikwelt auf einen Blick").font(.title2.bold())
                if let stats {
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        stat("Gespeichert", stats.savedEvents, "heart.fill")
                        stat("Geplant", stats.plannedEvents, "calendar.badge.checkmark")
                        stat("Besucht", stats.visitedEvents, "checkmark.seal.fill")
                        stat("Personen", stats.followedPersons, "person.fill")
                        stat("Ensembles", stats.followedEnsembles, "person.3.fill")
                        stat("Orte", stats.followedVenues, "building.columns.fill")
                        stat("Werke", stats.followedWorks, "music.note.list")
                    }
                } else if auth.accessToken == nil { ContentUnavailableView("Anmeldung erforderlich", systemImage: "person.crop.circle.badge.exclamationmark") }
                else { ProgressView().frame(maxWidth: .infinity).padding() }
                Text("Wishlist, Konzertlisten, Interessen und Benachrichtigungen findest du direkt im Profil. Ein Konzert wird erst nach deiner Bestätigung als besucht gezählt.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Mein Klangradar").task { await load() }
    }

    private func stat(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).foregroundStyle(KlangradarTheme.accent); Text(value.formatted()).font(.title.bold()); Text(title).font(.subheadline).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading).padding(15).background(Color(uiColor: .secondarySystemGroupedBackground)).clipShape(.rect(cornerRadius: 20, style: .continuous))
    }

    @MainActor private func load() async { guard let repository, let token = auth.accessToken else { return }; stats = try? await repository.klangradarStats(token: token) }
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
