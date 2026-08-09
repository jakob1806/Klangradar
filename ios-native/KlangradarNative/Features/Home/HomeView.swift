import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var model: HomeViewModel
    @EnvironmentObject private var follows: FollowStore
    private let contentRepository: any ContentRepository
    private let usesPreviewData: Bool
    @State private var collections: [EditorialCollection] = []

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

                    EventRail(
                        title: model.hasPersonalizedInterests ? "Für dich" : "Für dich empfohlen",
                        events: Array(model.recommendedEvents.filter { $0.id != events.first?.id }.prefix(14))
                    )

                    EventRail(
                        title: "Heute in München",
                        events: events.dropFirst().filter { event in
                            event.startDate.map(Calendar.current.isDateInToday) ?? false
                        }
                    )

                    EventRail(
                        title: "In den nächsten 7 Tagen",
                        events: Array(events.dropFirst().filter(isWithinNextSevenDays).prefix(14))
                    )

                    EventRail(
                        title: "Dieses Wochenende",
                        events: Array(events.filter(isThisWeekend).prefix(14))
                    )

                    EventRail(
                        title: "Beliebt in München",
                        events: Array(model.popularEvents.prefix(14))
                    )

                    EventRail(
                        title: "Neu für dich entdecken",
                        events: Array(model.discoveryEvents.prefix(14))
                    )

                    EventRail(
                        title: "Oper & Musiktheater",
                        events: Array(events.filter { $0.matchesFeedTerms(["oper", "musiktheater", "ballett"]) }.prefix(14))
                    )

                    EventRail(
                        title: "Orchester & Sinfonik",
                        events: Array(events.filter { $0.matchesFeedTerms(["orchester", "sinfoni", "symphoni"]) }.prefix(14))
                    )

                    EventRail(
                        title: "Kammermusik & Recitals",
                        events: Array(events.filter { $0.matchesFeedTerms(["kammer", "recital", "klavierabend", "sonatenabend"]) }.prefix(14))
                    )

                    EventRail(
                        title: "Chor & Vokalmusik",
                        events: Array(events.filter { $0.matchesFeedTerms(["chor", "vokal", "lied", "requiem", "messe"]) }.prefix(14))
                    )

                    EventRail(
                        title: "Eintritt frei",
                        events: Array(events.filter { $0.isFree == true }.prefix(14))
                    )

                    EventRail(
                        title: "Demnächst in München",
                        // Nutzerfeedback: "zu wenig personalisiert" — Events,
                        // die zu den Interessen/Favoriten (Personen,
                        // Ensembles, Orte) passen, zuerst; innerhalb beider
                        // Gruppen bleibt die bisherige chronologische
                        // Reihenfolge erhalten (stabile Sortierung). Ohne
                        // Anmeldung/Interessen ist personalizedEntityIDs
                        // leer und die Reihenfolge bleibt exakt wie zuvor.
                        events: events.dropFirst()
                            .filter { event in
                                !(event.startDate.map(Calendar.current.isDateInToday) ?? false)
                            }
                            .sorted { lhs, rhs in
                                let lhsMatch = lhs.matchesPersonalization(model.personalizedEntityIDs)
                                let rhsMatch = rhs.matchesPersonalization(model.personalizedEntityIDs)
                                return lhsMatch && !rhsMatch
                            }
                    )

                    // Nutzerwunsch: "bestimmten Ensembles/Personen/Venues
                    // folgen, eigene Kategorie auf dem Homescreen nur für
                    // diese Person/Venue/Ensemble" — eine eigene Reihe pro
                    // gefolgter Entität statt eines gemeinsamen Sammel-
                    // Moduls, damit z.B. "Isarphilharmonie" als eigener,
                    // erkennbarer Titel erscheint. Nutzt dieselben Events,
                    // die ohnehin schon geladen sind (kein Zusatz-Request).
                    ForEach(followedSections(from: events)) { section in
                        EventRail(title: section.title, events: section.events)
                    }

                    if !collections.isEmpty {
                        CollectionRail(collections: collections)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .refreshable { await model.refresh() }
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

    /// Eine Reihe je gefolgter Person/Ensemble/Venue mit deren kommenden
    /// Events aus der bereits geladenen Liste — alphabetisch nach Name, nur
    /// Entitäten mit mindestens einem Treffer (keine leeren Reihen).
    private func followedSections(from events: [ConcertEvent]) -> [FollowedEntitySection] {
        var byID: [UUID: (name: String, events: [ConcertEvent])] = [:]

        func record(id: UUID?, name: String?, event: ConcertEvent) {
            guard let id, let name, !name.isEmpty else { return }
            byID[id, default: (name, [])].events.append(event)
        }

        for event in events {
            if let venue = event.venues, follows.isFollowing(kind: .venue, id: venue.id) {
                record(id: venue.id, name: venue.name, event: event)
            }
            for participant in event.eventParticipants ?? [] {
                if let person = participant.persons, let id = person.id, follows.isFollowing(kind: .person, id: id) {
                    record(id: id, name: person.name, event: event)
                }
                if let ensemble = participant.ensembles, let id = ensemble.id, follows.isFollowing(kind: .ensemble, id: id) {
                    record(id: id, name: ensemble.name, event: event)
                }
            }
        }

        return byID
            .map { FollowedEntitySection(id: $0.key, title: $0.value.name, events: $0.value.events) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func isWithinNextSevenDays(_ event: ConcertEvent) -> Bool {
        guard let date = event.startDate,
              let end = Calendar.current.date(byAdding: .day, value: 7, to: .now) else { return false }
        return date >= .now && date <= end && !Calendar.current.isDateInToday(date)
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
                                .clipShape(.rect(cornerRadius: 22))
                                Text(collection.title).font(.headline)
                                if let subtitle = collection.subtitle {
                                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .frame(width: 280, alignment: .leading)
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
        let day = Calendar.current.isDateInToday(date) ? "HEUTE" : date.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.abbreviated).day().month(.abbreviated)).uppercased()
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
