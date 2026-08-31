import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded([ConcertEvent])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    // Nutzerfeedback: "Demnächst in München" ist "zu wenig personalisiert" —
    // IDs aus Interessen/Favoriten (Personen, Ensembles, Orte), gegen die
    // HomeView Events boosten kann (Treffer zuerst, sonst chronologisch wie
    // bisher). Leer, solange nicht angemeldet oder ohne gepflegte
    // Interessen — HomeView fällt dann automatisch auf rein chronologisch
    // zurück (unverändertes bisheriges Verhalten).
    @Published private(set) var personalizedEntityIDs: Set<UUID> = []
    @Published private(set) var hasPersonalizedInterests = false
    @Published private(set) var recommendedEvents: [ConcertEvent] = []
    @Published private(set) var discoveryEvents: [ConcertEvent] = []
    @Published private(set) var popularEvents: [ConcertEvent] = []
    @Published private(set) var favoriteEvents: [ConcertEvent] = []

    let repository: any EventRepository
    var currentUserID: UUID? { auth?.userID }
    var regionID: UUID?
    private let auth: AuthStore?
    private let userRepository: UserRepository?
    private var authCancellable: AnyCancellable?
    private var hasStartedLoading = false
    private var didCorrectForReadyAuth = false

    init(
        repository: any EventRepository,
        auth: AuthStore? = nil,
        userRepository: UserRepository? = nil
    ) {
        self.repository = repository
        self.auth = auth
        self.userRepository = userRepository
        // Nutzerfeedback: "ganz oben steht immer erst 'Für dich empfohlen'
        // statt 'Für dich', erst nach dem Aktualisieren die richtige,
        // personalisierte Kategorie" — RootTabView startet auth.bootstrap()
        // und HomeView.load() als parallele .task-Modifier, daher kann
        // load() schon losgelaufen sein, bevor die Session wiederhergestellt
        // ist. Sobald AuthStore fertig ist (state verlässt .loading),
        // einmalig still nachladen, falls load() vorher schon lief.
        authCancellable = auth?.$state.sink { [weak self] authState in
            guard let self, self.hasStartedLoading, !self.didCorrectForReadyAuth else { return }
            if case .loading = authState { return }
            self.didCorrectForReadyAuth = true
            let isInitialLoad: Bool
            if case .loading = self.state { isInitialLoad = true } else { isInitialLoad = false }
            Task {
                await self.refresh(
                    showsLoading: isInitialLoad,
                    usesCacheOnFailure: isInitialLoad
                )
            }
        }
    }

    /// Beim ersten Öffnen gilt Netzwerk-vor-Cache: Ein Snapshot darf nicht
    /// kurz alte Bilder oder eine unpersonalisierte Rail zeigen. Der Cache
    /// bleibt als echter Offline-Fallback erhalten.
    func load() async {
        guard case .idle = state else { return }
        hasStartedLoading = true
        if let auth, case .loading = auth.state {
            state = .loading
            return
        }
        await refresh(showsLoading: true, usesCacheOnFailure: true)
    }

    func refresh() async { await refresh(showsLoading: true, usesCacheOnFailure: false) }

    /// Von HomeView bei Änderung von `cityStore.selectedCity` aufgerufen --
    /// nur bei einer tatsächlichen Änderung neu laden, sonst würde jeder
    /// erneute Aufruf (auch mit demselben Wert) unnötig neu laden.
    func setRegion(_ regionID: UUID?) async {
        guard self.regionID != regionID else { return }
        self.regionID = regionID
        await refresh(showsLoading: true, usesCacheOnFailure: false)
    }

    private func applySnapshot(_ snapshot: HomeSnapshot) {
        state = .loaded(snapshot.events)
        recommendedEvents = snapshot.recommendedEvents
        discoveryEvents = snapshot.discoveryEvents
        popularEvents = snapshot.popularEvents
        personalizedEntityIDs = Set(snapshot.personalizedEntityIDs)
        hasPersonalizedInterests = snapshot.hasPersonalizedInterests
    }

    private func refresh(showsLoading: Bool, usesCacheOnFailure: Bool = false) async {
        // showsLoading: false bei der stillen Hintergrund-Revalidierung nach
        // einem Cache-Treffer bzw. nach dem Auth-Ready-Nachladen — sonst
        // würde der gerade gezeigte Stand durch einen Ladespinner ersetzt,
        // obwohl schon etwas zu sehen ist.
        if showsLoading { state = .loading }
        do {
            // Nutzerfeedback: "Demnächst in München" hat "zu wenig
            // vorgeschlagen" — 40 war zu knapp, sobald "Heute in München"
            // schon ein paar Events abzieht und danach noch personalisiert
            // sortiert wird. 100 deckt realistisch mehrere Wochen ab.
            let events = try await repository.upcomingEvents(limit: 100, regionID: regionID)
            async let enrichedTask: [ConcertEvent]? = try? repository.enrichingImages(in: events)
            async let personalizedTask = loadPersonalizedEntityIDs()
            async let modulesTask = loadHomeModules()
            async let favoritesTask = fetchFavoriteEvents()
            let enriched = await enrichedTask
            let personalization = await personalizedTask
            let modules = await modulesTask
            personalizedEntityIDs = personalization.ids
            hasPersonalizedInterests = personalization.hasAny
            let recommended = await enrich(modules.recommended)
            let discovery = await enrich(modules.discovery)
            let popular = await enrich(modules.popular)
            recommendedEvents = recommended
            discoveryEvents = discovery
            popularEvents = popular
            favoriteEvents = await favoritesTask
            let finalEvents = enriched ?? events
            state = .loaded(finalEvents)
            HomeCache.save(HomeSnapshot(
                events: finalEvents,
                recommendedEvents: recommended,
                discoveryEvents: discovery,
                popularEvents: popular,
                personalizedEntityIDs: Array(personalization.ids),
                hasPersonalizedInterests: personalization.hasAny,
                userID: auth?.userID,
                savedAtTimestamp: Date().timeIntervalSince1970
            ))
        } catch {
            // Stille Revalidierung, die scheitert (z. B. offline): der
            // bereits angezeigte Cache-Stand bleibt stehen statt eines
            // Fehlerbildschirms — nur der explizite Ladefall zeigt den
            // Fehler.
            if usesCacheOnFailure, let cached = HomeCache.load(for: auth?.userID) {
                applySnapshot(cached)
            } else if showsLoading {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func loadPersonalizedEntityIDs() async -> (ids: Set<UUID>, hasAny: Bool) {
        guard let auth, let userRepository, let userID = auth.userID, let token = auth.accessToken else {
            return ([], false)
        }
        async let genres = try? userRepository.selectedInterests(.genre, userID: userID, token: token)
        async let works = try? userRepository.selectedInterests(.work, userID: userID, token: token)
        async let persons = try? userRepository.selectedInterests(.person, userID: userID, token: token)
        async let ensembles = try? userRepository.selectedInterests(.ensemble, userID: userID, token: token)
        async let venues = try? userRepository.selectedInterests(.venue, userID: userID, token: token)
        let genreIDs = (await genres) ?? []
        let workIDs = (await works) ?? []
        let entityIDs = ((await persons) ?? []).union((await ensembles) ?? []).union((await venues) ?? [])
        return (Set(entityIDs.compactMap(UUID.init(uuidString:))), !genreIDs.isEmpty || !workIDs.isEmpty || !entityIDs.isEmpty)
    }

    private func loadHomeModules() async -> (recommended: [ConcertEvent], discovery: [ConcertEvent], popular: [ConcertEvent]) {
        guard let userRepository else { return ([], [], []) }
        let token = auth?.accessToken
        async let recommended = try? userRepository.recommendedEvents(limit: 16, token: token)
        async let popular = try? userRepository.popularEvents(limit: 16, token: token)
        let discovery: [ConcertEvent]
        if let token {
            discovery = (try? await userRepository.discoveryEvents(limit: 16, token: token)) ?? []
        } else {
            discovery = []
        }
        return ((await recommended) ?? [], discovery, (await popular) ?? [])
    }

    /// Favoriten sind keine Teilmenge der normalen Home-Abfrage: diese lädt
    /// bewusst nur die nächsten 100 Termine. Die eigene Favoritenabfrage
    /// verhindert, dass ein gespeichertes Konzert deshalb aus der Rail
    /// verschwindet, und liefert die vollständigen Karten-Daten inklusive
    /// Bild, Venue und Mitwirkenden.
    func loadFavoriteEvents() async {
        favoriteEvents = await fetchFavoriteEvents()
    }

    private func fetchFavoriteEvents() async -> [ConcertEvent] {
        guard let userRepository, let userID = auth?.userID, let token = auth?.accessToken else { return [] }
        let loaded = (try? await userRepository.favoriteEvents(userID: userID, token: token)) ?? []
        let enriched = (try? await repository.enrichingImages(in: loaded)) ?? loaded
        return enriched
            .filter { ($0.startDate ?? .distantPast) >= Date() }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private func enrich(_ events: [ConcertEvent]) async -> [ConcertEvent] {
        guard !events.isEmpty else { return [] }
        return (try? await repository.enrichingImages(in: events)) ?? events
    }
}

extension ConcertEvent {
    /// Trifft eines der Interessen-/Favoriten-IDs (Ort, Mitwirkende) —
    /// siehe HomeViewModel.personalizedEntityIDs.
    func matchesPersonalization(_ ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return false }
        if let venueID = venues?.id, ids.contains(venueID) { return true }
        return eventParticipants?.contains { participant in
            if let id = participant.persons?.id, ids.contains(id) { return true }
            if let id = participant.ensembles?.id, ids.contains(id) { return true }
            return false
        } ?? false
    }
}
