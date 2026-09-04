import SwiftUI

enum HomeRecommendationCategory: String, CaseIterable, Codable, Identifiable {
    case forYou, today, nextSevenDays, weekend, popular, discover
    case opera, orchestra, chamber, choir, free, upcoming, editorialCollections
    case favorites, taste, entitySpotlight, followed
    case followedPersons, followedEnsembles, followedVenues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "Für dich"
        case .today: "Heute in München"
        case .nextSevenDays: "In den nächsten 7 Tagen"
        case .weekend: "Dieses Wochenende"
        case .popular: "Beliebt in München"
        case .discover: "Neu für dich entdecken"
        case .opera: "Oper & Musiktheater"
        case .orchestra: "Orchester & Sinfonik"
        case .chamber: "Kammermusik & Recitals"
        case .choir: "Chor & Vokalmusik"
        case .free: "Eintritt frei"
        case .upcoming: "Demnächst in München"
        case .favorites: "Deine Favoriten"
        case .taste: "Nach deinem Geschmack"
        case .entitySpotlight: "Von dir gefolgt"
        case .followed: "Gefolgt"
        case .editorialCollections: "Redaktionelle Sammlungen"
        case .followedPersons: "Gefolgte Personen"
        case .followedEnsembles: "Gefolgte Ensembles"
        case .followedVenues: "Gefolgte Orte"
        }
    }

    var symbol: String {
        switch self {
        case .forYou: "sparkles"
        case .today: "sun.max"
        case .nextSevenDays: "calendar.badge.clock"
        case .weekend: "calendar"
        case .popular: "flame"
        case .discover: "safari"
        case .opera: "theatermasks"
        case .orchestra: "music.note.list"
        case .chamber: "music.quarternote.3"
        case .choir: "person.3"
        case .free: "eurosign.circle"
        case .upcoming: "clock"
        case .favorites: "heart.fill"
        case .taste: "wand.and.stars"
        case .entitySpotlight: "music.note.house"
        case .followed: "person.crop.circle.badge.checkmark"
        case .editorialCollections: "rectangle.stack"
        case .followedPersons: "person.crop.circle.badge.checkmark"
        case .followedEnsembles: "person.3.fill"
        case .followedVenues: "mappin.circle.fill"
        }
    }

    // Die granularen followedPersons/followedEnsembles/followedVenues-Reihen
    // decken denselben Zweck wie `.followed`/`.entitySpotlight` ab, zeigen
    // aber jede gefolgte Entität einzeln statt in einem gemischten/nur-besten
    // Feed — deshalb Standardreihenfolge auf die granulare Variante, `.followed`
    // und `.entitySpotlight` bleiben über "Homepage anordnen" weiter wählbar.
    static let defaultOrder: [HomeRecommendationCategory] = [
        .today, .favorites, .followedPersons, .followedEnsembles, .followedVenues,
        .forYou, .taste, .discover,
        .nextSevenDays, .weekend, .popular, .editorialCollections,
        .opera, .orchestra, .chamber, .choir, .free, .upcoming
    ]
}

enum HomeCategoryPreferences {
    static let didChange = Notification.Name("HomeCategoryPreferencesDidChange")
    private static let fallbackKey = "homeRecommendationCategoryOrder.current"

    private static func key(for userID: UUID?) -> String {
        "homeRecommendationCategoryOrder.\(userID?.uuidString ?? "guest")"
    }

    static func order(for userID: UUID?) -> [HomeRecommendationCategory] {
        guard let values = UserDefaults.standard.stringArray(forKey: key(for: userID))
            ?? UserDefaults.standard.stringArray(forKey: fallbackKey) else {
            return HomeRecommendationCategory.defaultOrder
        }
        let saved = values.compactMap(HomeRecommendationCategory.init(rawValue:))
        let missing = HomeRecommendationCategory.defaultOrder.filter { !saved.contains($0) }
        return saved + missing
    }

    static func save(_ order: [HomeRecommendationCategory], for userID: UUID?) {
        let values = order.map(\.rawValue)
        UserDefaults.standard.set(values, forKey: key(for: userID))
        // Stabiler Fallback während AuthStore beim App-Start seine Session
        // wiederherstellt und userID kurzzeitig nil sein kann.
        UserDefaults.standard.set(values, forKey: fallbackKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func reset(for userID: UUID?) {
        UserDefaults.standard.removeObject(forKey: key(for: userID))
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var model: HomeViewModel
    @EnvironmentObject private var favorites: FavoriteStore
    @EnvironmentObject private var follows: FollowStore
    @EnvironmentObject private var cityStore: CityStore
    private let contentRepository: any ContentRepository
    private let usesPreviewData: Bool
    private let auth: AuthStore?
    private let userRepository: UserRepository?
    @State private var collections: [EditorialCollection] = []
    @State private var categoryOrder: [HomeRecommendationCategory] = HomeRecommendationCategory.defaultOrder
    @State private var personDirectory: [DirectoryItem] = []
    @State private var ensembleDirectory: [DirectoryItem] = []

    init(
        repository: any EventRepository,
        contentRepository: any ContentRepository,
        usesPreviewData: Bool,
        auth: AuthStore? = nil,
        userRepository: UserRepository? = nil
    ) {
        _model = StateObject(wrappedValue: HomeViewModel(repository: repository, auth: auth, userRepository: userRepository))
        self.contentRepository = contentRepository
        self.usesPreviewData = usesPreviewData
        self.auth = auth
        self.userRepository = userRepository
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground()
                    .ignoresSafeArea()

                content
                    .frame(maxWidth: KlangradarTheme.contentMaxWidth)
            }
            // Nutzerwunsch: "Klangradar" soll linksbündig stehen (nicht als
            // UIKit-Standard-.large-Titel) — derselbe eigene .topBarLeading-
            // Titel wie in SearchView ("Suche"). Nutzerfeedback zusätzlich:
            // ein sichtbarer Rand/breiter Blur-Streifen blieb zwischen
            // Hintergrund und Titelleiste bestehen, obwohl der Chip selbst
            // kein doppeltes Glas mehr zeigte — das ist iOS 26s automatischer
            // "Scroll Edge Effect" der Titelleiste selbst, ein GESONDERTER
            // Mechanismus von .sharedBackgroundVisibility (das nur einzelne
            // ToolbarItems betrifft). .toolbarBackgroundVisibility(.hidden)
            // ist die iOS-26-Entsprechung, die genau diesen Streifen
            // unterdrückt; .toolbarBackground(.hidden) bleibt als Fallback
            // für iOS 17–25 (kein automatisches Scroll-Glas dort).
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Klangradar").font(.headline.bold()).fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("Klangradar").font(.headline.bold()).fixedSize()
                    }
                }
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore)
                    }
                }
            }
            .modifier(HiddenScrollEdgeNavigationBar())
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(event: event, repository: model.repository, contentRepository: contentRepository)
            }
            .navigationDestination(for: EditorialCollection.self) { collection in
                CollectionDetailView(collection: collection, repository: contentRepository, eventRepository: model.repository)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                EntityDetailView(route: route, repository: contentRepository)
            }
            .task {
                // Nutzerfeedback: "Stadtfilter klappt nicht, trotz München
                // werden Berlin-Konzerte gezeigt" -- diese Zuweisung fehlte
                // nach einem Merge komplett, model.regionID blieb dauerhaft
                // nil (= alle Städte), unabhängig vom Chip oben rechts.
                model.regionID = cityStore.selectedCity?.id
                await model.load()
                collections = (try? await contentRepository.collections()) ?? []
                async let persons = contentRepository.directory(kind: .person)
                async let ensembles = contentRepository.directory(kind: .ensemble)
                personDirectory = (try? await persons) ?? []
                ensembleDirectory = (try? await ensembles) ?? []
            }
            .onAppear {
                categoryOrder = HomeCategoryPreferences.order(for: model.currentUserID)
            }
            .onReceive(NotificationCenter.default.publisher(for: HomeCategoryPreferences.didChange)) { _ in
                categoryOrder = HomeCategoryPreferences.order(for: model.currentUserID)
            }
            .onChange(of: cityStore.selectedCity) { _, newCity in
                Task { await model.setRegion(newCity?.id) }
            }
            // Eine Änderung im Herz-Button wirkt sofort auch auf die
            // Startseite. Die Rail verwendet dabei die vollständige
            // Favoritenabfrage statt nur die zufällig gerade geladenen
            // kommenden 100 Veranstaltungen.
            .onChange(of: favorites.ids) { _, _ in
                Task { await model.loadFavoriteEvents() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Konzerte werden geladen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            ContentUnavailableView {
                Label("Laden fehlgeschlagen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") {
                    Task { await model.refresh() }
                }
            }

        case let .loaded(events):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    if usesPreviewData {
                        previewNotice
                    }

                    if let hero = events.first {
                        NavigationLink(value: hero) {
                            HeroEventView(event: hero, height: horizontalSizeClass == .regular ? 280 : 224)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(categoryOrder) { category in
                        recommendationSection(category, events: events)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder
    private func recommendationSection(_ category: HomeRecommendationCategory, events: [ConcertEvent]) -> some View {
        switch category {
        case .forYou:
            // Die RPC-Empfehlungen können leer sein (z. B. bei einer neuen
            // Session oder während die Interessen noch geladen werden). Die
            // Kategorie „Für dich“ bleibt trotzdem sichtbar: persönliche
            // Treffer haben Vorrang, danach folgen die Server-Empfehlungen
            // und zuletzt kommende Events als sinnvoller Fallback.
            EventRail(title: category.title, events: forYouEvents(from: events))
        case .favorites:
            EventRail(title: category.title, events: Array(model.favoriteEvents.prefix(14)))
        case .taste:
            let spotlight = tasteSpotlight(from: events)
            EventRail(title: spotlight.title, events: spotlight.events)
        case .entitySpotlight:
            let spotlight = entitySpotlight(from: events)
            EventRail(title: spotlight.title, events: spotlight.events)
        case .today:
            EventRail(title: category.title, events: events.dropFirst().filter { $0.startDate.map(KlangradarDateTime.calendar.isDateInToday) ?? false })
        case .nextSevenDays:
            EventRail(title: category.title, events: Array(events.dropFirst().filter(isWithinNextSevenDays).prefix(14)))
        case .weekend:
            EventRail(title: category.title, events: Array(events.filter(isThisWeekend).prefix(14)))
        case .popular:
            EventRail(title: category.title, events: Array(model.popularEvents.prefix(14)))
        case .discover:
            EventRail(title: category.title, events: Array(model.discoveryEvents.prefix(14)))
        case .opera:
            EventRail(title: category.title, events: Array(events.filter { $0.matchesFeedTerms(["oper", "musiktheater", "ballett"]) }.prefix(14)))
        case .orchestra:
            EventRail(title: category.title, events: Array(events.filter { $0.matchesFeedTerms(["orchester", "sinfoni", "symphoni"]) }.prefix(14)))
        case .chamber:
            EventRail(title: category.title, events: Array(events.filter { $0.matchesFeedTerms(["kammer", "recital", "klavierabend", "sonatenabend"]) }.prefix(14)))
        case .choir:
            EventRail(title: category.title, events: Array(events.filter { $0.matchesFeedTerms(["chor", "vokal", "lied", "requiem", "messe"]) }.prefix(14)))
        case .free:
            EventRail(title: category.title, events: Array(events.filter { $0.isFree == true }.prefix(14)))
        case .upcoming:
            EventRail(title: category.title, events: events.dropFirst().filter { !($0.startDate.map(KlangradarDateTime.calendar.isDateInToday) ?? false) }.sorted { lhs, rhs in
                lhs.matchesPersonalization(model.personalizedEntityIDs) && !rhs.matchesPersonalization(model.personalizedEntityIDs)
            })
        case .followed:
            // Auch ältere gespeicherte Startseiten-Konfigurationen können
            // noch die frühere Sammelkategorie „Gefolgt“ enthalten. Personen
            // und Ensembles erscheinen darin nun ebenfalls als runde Profile
            // statt wieder in rechteckige Veranstaltungskarten zurückzufallen.
            EntityRail(title: "Gefolgte Personen", items: followedPersonDirectoryItems)
            EntityRail(title: "Gefolgte Ensembles", items: followedEnsembleDirectoryItems)
        case .editorialCollections:
            if !collections.isEmpty { CollectionRail(collections: collections) }
        case .followedPersons:
            EntityRail(title: category.title, items: followedPersonDirectoryItems)
        case .followedEnsembles:
            EntityRail(title: category.title, items: followedEnsembleDirectoryItems)
        case .followedVenues:
            ForEach(followedSections(from: events, kind: .venue)) { section in
                EventRail(title: section.title, events: section.events)
            }
        }
    }

    private var previewNotice: some View {
        Label(
            "Preview-Daten – Supabase noch nicht konfiguriert",
            systemImage: "hammer"
        )
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, KlangradarTheme.pagePadding)
    }

    private var followedEnsembleDirectoryItems: [DirectoryItem] {
        followedDirectoryItems(personDirectory: ensembleDirectory, kind: .ensemble)
    }

    private var followedPersonDirectoryItems: [DirectoryItem] {
        followedDirectoryItems(personDirectory: personDirectory, kind: .person)
    }

    private func followedDirectoryItems(personDirectory: [DirectoryItem], kind: EntityKind) -> [DirectoryItem] {
        personDirectory
            .filter { item in
                guard let id = UUID(uuidString: item.id) else { return false }
                return follows.isFollowing(kind: kind, id: id)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Eine Reihe je gefolgter Entität der gegebenen Art mit deren kommenden
    /// Events aus der bereits geladenen Liste — alphabetisch nach Name, nur
    /// Entitäten mit mindestens einem Treffer (keine leeren Reihen).
    private func followedSections(from events: [ConcertEvent], kind: EntityKind) -> [FollowedEntitySection] {
        var byID: [UUID: (name: String, events: [ConcertEvent])] = [:]

        func record(id: UUID?, name: String?, event: ConcertEvent) {
            guard let id, let name, !name.isEmpty, follows.isFollowing(kind: kind, id: id) else { return }
            byID[id, default: (name, [])].events.append(event)
        }

        for event in events {
            switch kind {
            case .venue:
                record(id: event.venues?.id, name: event.venues?.name, event: event)
            case .person:
                for participant in event.eventParticipants ?? [] {
                    record(id: participant.persons?.id, name: participant.persons?.name, event: event)
                }
            case .ensemble:
                for participant in event.eventParticipants ?? [] {
                    record(id: participant.ensembles?.id, name: participant.ensembles?.name, event: event)
                }
            case .work:
                break
            }
        }

        return byID
            .map { FollowedEntitySection(id: $0.key, title: $0.value.name, events: $0.value.events) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Eine bewusst gemischte Rail: Person, Ensemble und Spielstätte sind
    /// Signale für dasselbe Konzert, nicht drei getrennte Inhalts-Silos.
    /// Ergänzt die granularen `followedSections`-Reihen um eine kombinierte
    /// Ansicht (Kategorie `.followed`), falls Nutzer diese statt/zusätzlich
    /// zu den einzelnen Reihen in "Homepage anordnen" wählen.
    private func followedEvents(from events: [ConcertEvent]) -> [ConcertEvent] {
        Array(events.filter { event in
            if let venue = event.venues, follows.isFollowing(kind: .venue, id: venue.id) { return true }
            return event.eventParticipants?.contains { participant in
                if let id = participant.persons?.id, follows.isFollowing(kind: .person, id: id) { return true }
                if let id = participant.ensembles?.id, follows.isFollowing(kind: .ensemble, id: id) { return true }
                return false
            } ?? false
        }.prefix(14))
    }

    private func forYouEvents(from events: [ConcertEvent]) -> [ConcertEvent] {
        let withoutHero = events.filter { $0.id != events.first?.id }
        let personalized = withoutHero.filter { $0.matchesPersonalization(model.personalizedEntityIDs) }
        let serverRecommended = model.recommendedEvents.filter { $0.id != events.first?.id }

        // IDs statt Titel vergleichen: gleichnamige Aufführungen an
        // unterschiedlichen Tagen bleiben eigenständige Empfehlungen.
        var seen = Set<UUID>()
        var result: [ConcertEvent] = []
        for event in personalized + serverRecommended + withoutHero where seen.insert(event.id).inserted {
            result.append(event)
            if result.count == 14 { break }
        }
        return result
    }

    private func tasteSpotlight(from events: [ConcertEvent]) -> (title: String, events: [ConcertEvent]) {
        let labels = model.recommendedEvents.flatMap(\.genreLabels).filter { !$0.isEmpty }
        let dominant = Dictionary(grouping: labels, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        guard let dominant else { return ("Mehr von dem, was du magst", []) }
        let matches = events.filter { $0.genreLabels.contains(dominant) && !favorites.ids.contains($0.id) }
        return ("Mehr \(dominant) für dich", Array(matches.prefix(14)))
    }

    private func entitySpotlight(from events: [ConcertEvent]) -> (title: String, events: [ConcertEvent]) {
        var groups: [String: (title: String, events: [ConcertEvent])] = [:]
        func add(key: String, title: String, event: ConcertEvent) {
            groups[key, default: (title, [])].events.append(event)
        }
        for event in events {
            if let venue = event.venues, follows.isFollowing(kind: .venue, id: venue.id) {
                add(key: "venue:\(venue.id)", title: "Konzerte im \(venue.name)", event: event)
            }
            for participant in event.eventParticipants ?? [] {
                if let person = participant.persons, let id = person.id, let name = person.name, follows.isFollowing(kind: .person, id: id) {
                    add(key: "person:\(id)", title: "Konzerte mit \(name)", event: event)
                }
                if let ensemble = participant.ensembles, let id = ensemble.id, let name = ensemble.name, follows.isFollowing(kind: .ensemble, id: id) {
                    add(key: "ensemble:\(id)", title: "Konzerte von \(name)", event: event)
                }
            }
        }
        guard let best = groups.values.filter({ $0.events.count >= 2 }).max(by: { $0.events.count < $1.events.count }) else {
            return ("Von dir gefolgt", [])
        }
        return (best.title, Array(best.events.prefix(14)))
    }

    private func isWithinNextSevenDays(_ event: ConcertEvent) -> Bool {
        guard let date = event.startDate,
              let end = KlangradarDateTime.calendar.date(byAdding: .day, value: 7, to: .now) else { return false }
        return date >= .now && date <= end && !KlangradarDateTime.calendar.isDateInToday(date)
    }

    private func isThisWeekend(_ event: ConcertEvent) -> Bool {
        guard let date = event.startDate else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: date)
        guard weekday == 1 || weekday == 7 else { return false }

        let today = calendar.startOfDay(for: .now)
        let daysUntilSaturday = (7 - calendar.component(.weekday, from: today) + 7) % 7
        guard let saturday = calendar.date(byAdding: .day, value: daysUntilSaturday, to: today),
              let monday = calendar.date(byAdding: .day, value: 2, to: saturday) else { return false }
        return date >= saturday && date < monday
    }
}

private struct FollowedEntitySection: Identifiable {
    let id: UUID
    let title: String
    let events: [ConcertEvent]
}

private struct EntityRail: View {
    let title: String
    let items: [DirectoryItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, KlangradarTheme.pagePadding)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(items) { item in
                            NavigationLink(value: EntityRoute(kind: item.kind, identifier: item.slug ?? item.id)) {
                                VStack(spacing: 8) {
                                    CroppedAsyncImage(url: item.imageURL, crop: item.avatarCrop) {
                                        Color.secondary.opacity(0.12)
                                            .overlay { Image(systemName: item.kind.systemImage) }
                                    }
                                    .frame(width: 92, height: 92)
                                    .clipShape(Circle())
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 100)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct CollectionRail: View {
    let collections: [EditorialCollection]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Redaktionelle Sammlungen")
                .font(.title2.bold())
                .padding(.horizontal, KlangradarTheme.pagePadding)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(collections) { collection in
                        NavigationLink(value: collection) {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: collection.coverImageURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(.quaternary)
                                        .overlay { Image(systemName: "sparkles") }
                                }
                                .frame(width: 280, height: 160)
                                .clipped()
                                .clipShape(.rect(cornerRadius: 22))
                                Text(collection.title).font(.headline).lineLimit(1)
                                if let subtitle = collection.subtitle {
                                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                } else {
                                    Text(" ").font(.subheadline).hidden()
                                }
                            }
                            .frame(width: 280, height: 222, alignment: .topLeading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct HeroEventView: View {
    let event: ConcertEvent
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            EventArtwork(event: event)
                .frame(width: proxy.size.width, height: height)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.16), location: 0.28),
                            .init(color: .black.opacity(0.86), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(height * 0.72, 170))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(heroDate(event))
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.9))

                        Text(event.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(event.subtitle ?? event.venueName, systemImage: "mappin")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.34), radius: 7, y: 2)
                    .padding(18)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .clipShape(.rect(cornerRadius: 24))
        }
        .frame(height: height)
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .accessibilityElement(children: .combine)
    }

    private func heroDate(_ event: ConcertEvent) -> String {
        guard let date = event.startDate else { return "NÄCHSTE VERANSTALTUNG" }
        let day = KlangradarDateTime.calendar.isDateInToday(date) ? "HEUTE" : KlangradarDateTime.string(date, format: "EEE, d. MMM").uppercased()
        return "\(day) · \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct EventRail: View {
    let title: String
    let events: [ConcertEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, KlangradarTheme.pagePadding)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(events) { event in
                        NavigationLink(value: event) {
                            EventCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
            .scrollIndicators(.hidden)
            }
        }
    }
}
