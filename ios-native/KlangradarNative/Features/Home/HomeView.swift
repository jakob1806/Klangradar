import SwiftUI

enum HomeRecommendationCategory: String, CaseIterable, Codable, Identifiable {
    case forYou, today, nextSevenDays, weekend, popular, discover
    case opera, orchestra, chamber, choir, free, upcoming, editorialCollections
    case favorites, followedPersons, followedEnsembles, followedVenues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: "Für dich empfohlen"
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
        case .editorialCollections: "Redaktionelle Sammlungen"
        case .favorites: "Favoriten"
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
        case .editorialCollections: "rectangle.stack"
        case .favorites: "heart.fill"
        case .followedPersons: "person.crop.circle.badge.checkmark"
        case .followedEnsembles: "person.3.fill"
        case .followedVenues: "mappin.circle.fill"
        }
    }

    static let defaultOrder = allCases
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
    @EnvironmentObject private var follows: FollowStore
    @EnvironmentObject private var favorites: FavoriteStore
    private let contentRepository: any ContentRepository
    private let usesPreviewData: Bool
    @State private var collections: [EditorialCollection] = []
    @State private var categoryOrder: [HomeRecommendationCategory] = HomeRecommendationCategory.defaultOrder

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
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground()
                    .ignoresSafeArea()

                content
                    .frame(maxWidth: KlangradarTheme.contentMaxWidth)
            }
            .navigationTitle("Klangradar")
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(event: event, repository: model.repository, contentRepository: contentRepository)
            }
            .navigationDestination(for: EditorialCollection.self) { collection in
                CollectionDetailView(collection: collection, repository: contentRepository, eventRepository: model.repository)
            }
            .task {
                await model.load()
                collections = (try? await contentRepository.collections()) ?? []
            }
            .onAppear {
                categoryOrder = HomeCategoryPreferences.order(for: model.currentUserID)
            }
            .onReceive(NotificationCenter.default.publisher(for: HomeCategoryPreferences.didChange)) { _ in
                categoryOrder = HomeCategoryPreferences.order(for: model.currentUserID)
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
            EventRail(title: model.hasPersonalizedInterests ? "Für dich" : "Für dich empfohlen", events: Array(model.recommendedEvents.filter { $0.id != events.first?.id }.prefix(14)))
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
        case .editorialCollections:
            if !collections.isEmpty { CollectionRail(collections: collections) }
        case .favorites:
            EventRail(title: category.title, events: Array(events.filter { favorites.ids.contains($0.id) }.prefix(14)))
        case .followedPersons:
            ForEach(followedSections(from: events, kind: .person)) { section in
                EventRail(title: section.title, events: section.events)
            }
        case .followedEnsembles:
            ForEach(followedSections(from: events, kind: .ensemble)) { section in
                EventRail(title: section.title, events: section.events)
            }
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
