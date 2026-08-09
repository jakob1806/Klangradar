import Foundation

struct NotificationPreferences: Sendable {
    var newMatchingEvents = true
    var priceChanges = true
    var almostSoldOut = true
    var reminderDayBefore = true
    var followedEnsembleNewEvent = true
}

enum InterestCategory: String, CaseIterable, Sendable {
    case genre, person, ensemble, venue
    var title: String { switch self { case .genre: "Genres"; case .person: "Personen"; case .ensemble: "Ensembles"; case .venue: "Orte" } }
    var systemImage: String { switch self { case .genre: "music.quarternote.3"; case .person: "person"; case .ensemble: "person.3"; case .venue: "building.columns" } }
}
struct InterestOption: Identifiable, Hashable, Sendable { let id: String; let label: String }

struct UserRepository: Sendable {
    let client: SupabaseRESTClient

    func favoriteEvents(userID: UUID, token: String) async throws -> [ConcertEvent] {
        let rows: [JSONObject] = try await client.get(table: "favorites", queryItems: [
            URLQueryItem(name: "select", value: "events(id,slug,title,subtitle,start_datetime,image_urls,status,venues(id,name))"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ], accessToken: token)
        return rows.compactMap { $0.object("events") }.compactMap(ConcertEvent.init(json:))
    }

    func favoriteIDs(userID: UUID, token: String) async throws -> Set<UUID> {
        let rows: [JSONObject] = try await client.get(table: "favorites", queryItems: [
            URLQueryItem(name: "select", value: "event_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ], accessToken: token)
        return Set(rows.compactMap { $0.string("event_id").flatMap(UUID.init(uuidString:)) })
    }

    func setFavorite(eventID: UUID, isFavorite: Bool, userID: UUID, token: String) async throws {
        if isFavorite {
            _ = try await client.insert(table: "favorites", values: ["user_id": .string(userID.uuidString), "event_id": .string(eventID.uuidString)], accessToken: token)
        } else {
            try await client.delete(table: "favorites", filters: [URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"), URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)")], accessToken: token)
        }
    }

    func preferences(userID: UUID, token: String) async throws -> NotificationPreferences {
        let rows: [JSONObject] = try await client.get(table: "notification_preferences", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: token)
        guard let row = rows.first else { return NotificationPreferences() }
        return NotificationPreferences(
            newMatchingEvents: row.bool("new_matching_events") ?? true,
            priceChanges: row.bool("price_changes") ?? true,
            almostSoldOut: row.bool("almost_sold_out") ?? true,
            reminderDayBefore: row.bool("reminder_day_before") ?? true,
            followedEnsembleNewEvent: row.bool("followed_ensemble_new_event") ?? true
        )
    }

    func setPreference(userID: UUID, token: String, column: String, value: Bool) async throws {
        try await client.upsert(table: "notification_preferences", values: [
            "user_id": .string(userID.uuidString), column: .bool(value)
        ], accessToken: token, conflictColumns: "user_id")
    }

    func interestOptions(_ category: InterestCategory) async throws -> [InterestOption] {
        let specification: (String, String, String)
        switch category {
        case .genre: specification = ("genres", "id,label_de", "sort_order")
        case .person: specification = ("persons", "id,full_name", "full_name")
        case .ensemble: specification = ("ensembles", "id,name", "name")
        case .venue: specification = ("venues", "id,name", "name")
        }
        var rows: [JSONObject] = []
        let pageSize = 500
        while true {
            let page: [JSONObject] = try await client.get(table: specification.0, queryItems: [
                URLQueryItem(name: "select", value: specification.1),
                URLQueryItem(name: "order", value: "\(specification.2).asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(rows.count))
            ])
            rows.append(contentsOf: page)
            if page.count < pageSize { break }
        }
        return rows.compactMap { row in guard let id = row.string("id"), let label = row.string("label_de") ?? row.string("full_name") ?? row.string("name") else { return nil }; return InterestOption(id: id, label: label) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func selectedInterests(_ category: InterestCategory, userID: UUID, token: String) async throws -> Set<String> {
        let (table, column) = interestStorage(category)
        let rows: [JSONObject] = try await client.get(table: table, queryItems: [URLQueryItem(name: "select", value: column), URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")], accessToken: token)
        return Set(rows.compactMap { $0.string(column) })
    }

    func setInterest(_ category: InterestCategory, id: String, selected: Bool, userID: UUID, token: String) async throws {
        let (table, column) = interestStorage(category)
        if selected { _ = try await client.insert(table: table, values: ["user_id": .string(userID.uuidString), column: .string(id)], accessToken: token) }
        else { try await client.delete(table: table, filters: [URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"), URLQueryItem(name: column, value: "eq.\(id)")], accessToken: token) }
    }

    private func interestStorage(_ category: InterestCategory) -> (String, String) {
        switch category { case .genre: ("profile_interest_genres", "genre_id"); case .person: ("user_favorite_persons", "person_id"); case .ensemble: ("user_favorite_ensembles", "ensemble_id"); case .venue: ("user_favorite_venues", "venue_id") }
    }
}

@MainActor
final class FavoriteStore: ObservableObject {
    @Published private(set) var ids: Set<UUID> = []
    private let auth: AuthStore
    private let repository: UserRepository?

    init(auth: AuthStore, repository: UserRepository?) { self.auth = auth; self.repository = repository }

    func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        ids = (try? await repository.favoriteIDs(userID: userID, token: token)) ?? []
    }

    func toggle(_ eventID: UUID) async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        let newValue = !ids.contains(eventID)
        if newValue { ids.insert(eventID) } else { ids.remove(eventID) }
        do { try await repository.setFavorite(eventID: eventID, isFavorite: newValue, userID: userID, token: token) }
        catch { if newValue { ids.remove(eventID) } else { ids.insert(eventID) } }
    }
}
