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

    let repository: any EventRepository
    private let auth: AuthStore?
    private let userRepository: UserRepository?

    init(
        repository: any EventRepository,
        auth: AuthStore? = nil,
        userRepository: UserRepository? = nil
    ) {
        self.repository = repository
        self.auth = auth
        self.userRepository = userRepository
    }

    func load() async {
        guard case .idle = state else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        do {
            // Nutzerfeedback: "Demnächst in München" hat "zu wenig
            // vorgeschlagen" — 40 war zu knapp, sobald "Heute in München"
            // schon ein paar Events abzieht und danach noch personalisiert
            // sortiert wird. 100 deckt realistisch mehrere Wochen ab.
            let events = try await repository.upcomingEvents(limit: 100)
            state = .loaded(events)
            async let enrichedTask: [ConcertEvent]? = try? repository.enrichingImages(in: events)
            async let personalizedTask = loadPersonalizedEntityIDs()
            let enriched = await enrichedTask
            personalizedEntityIDs = await personalizedTask
            if let enriched {
                state = .loaded(enriched)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadPersonalizedEntityIDs() async -> Set<UUID> {
        guard let auth, let userRepository, let userID = auth.userID, let token = auth.accessToken else {
            return []
        }
        async let persons = try? userRepository.selectedInterests(.person, userID: userID, token: token)
        async let ensembles = try? userRepository.selectedInterests(.ensemble, userID: userID, token: token)
        async let venues = try? userRepository.selectedInterests(.venue, userID: userID, token: token)
        let combined = ((await persons) ?? []).union((await ensembles) ?? []).union((await venues) ?? [])
        return Set(combined.compactMap(UUID.init(uuidString:)))
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
