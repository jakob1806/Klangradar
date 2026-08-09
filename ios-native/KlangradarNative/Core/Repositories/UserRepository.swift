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

struct UserEventList: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date?
    let events: [ConcertEvent]
}

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

    func eventLists(userID: UUID, token: String) async throws -> [UserEventList] {
        let rows: [JSONObject] = try await client.get(table: "favorite_lists", queryItems: [
            URLQueryItem(
                name: "select",
                value: "id,name,created_at,favorite_list_items(added_at,events(id,slug,title,subtitle,start_datetime,image_urls,status,category,is_free,venues(id,name,photo_url),event_genres(genres(id,slug,label_de))))"
            ),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)),
                  let name = row.string("name") else { return nil }
            let events = row.objects("favorite_list_items")
                .compactMap { $0.object("events") }
                .compactMap(ConcertEvent.init(json:))
                .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            return UserEventList(
                id: id,
                name: name,
                createdAt: row.string("created_at").flatMap(FlexibleDateParser.date(from:)),
                events: events
            )
        }
    }

    func createEventList(name: String, userID: UUID, token: String) async throws -> UserEventList? {
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !cleanName.isEmpty else { return nil }
        let rows = try await client.insert(
            table: "favorite_lists",
            values: ["user_id": .string(userID.uuidString), "name": .string(cleanName)],
            accessToken: token,
            returning: true
        )
        guard let row = rows.first,
              let id = row.string("id").flatMap(UUID.init(uuidString:)) else { return nil }
        return UserEventList(id: id, name: row.string("name") ?? cleanName, createdAt: nil, events: [])
    }

    func renameEventList(id: UUID, name: String, token: String) async throws {
        let cleanName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !cleanName.isEmpty else { return }
        try await client.update(
            table: "favorite_lists",
            values: ["name": .string(cleanName)],
            filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            accessToken: token
        )
    }

    func deleteEventList(id: UUID, token: String) async throws {
        try await client.delete(
            table: "favorite_lists",
            filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            accessToken: token
        )
    }

    func replaceEvents(in listID: UUID, selected: Set<UUID>, previous: Set<UUID>, token: String) async throws {
        for eventID in selected.subtracting(previous) {
            _ = try await client.insert(
                table: "favorite_list_items",
                values: ["list_id": .string(listID.uuidString), "event_id": .string(eventID.uuidString)],
                accessToken: token
            )
        }
        for eventID in previous.subtracting(selected) {
            try await client.delete(
                table: "favorite_list_items",
                filters: [
                    URLQueryItem(name: "list_id", value: "eq.\(listID.uuidString)"),
                    URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)")
                ],
                accessToken: token
            )
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

    func recommendedEvents(limit: Int = 16, token: String? = nil) async throws -> [ConcertEvent] {
        try await homeEvents(function: "recommended_events", limit: limit, token: token)
    }

    func discoveryEvents(limit: Int = 16, token: String) async throws -> [ConcertEvent] {
        try await homeEvents(function: "discovery_events", limit: limit, token: token)
    }

    func popularEvents(limit: Int = 16, token: String? = nil) async throws -> [ConcertEvent] {
        try await homeEvents(function: "popular_events", limit: limit, token: token)
    }

    private func homeEvents(function: String, limit: Int, token: String?) async throws -> [ConcertEvent] {
        let rows: [JSONObject] = try await client.rpc(
            function,
            parameters: ["p_result_limit": .number(Double(limit))],
            accessToken: token
        )
        return rows.compactMap { original in
            var row = original
            if var venue = row.object("venues"),
               venue.string("id") == nil,
               let venueID = row.string("venue_id") {
                venue["id"] = .string(venueID)
                row["venues"] = .object(venue)
            }
            if row.string("status") == nil { row["status"] = .string("scheduled") }
            return ConcertEvent(json: row)
        }
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

/// Nutzerwunsch: "bestimmten Ensembles/Personen/Venues folgen" direkt von
/// der jeweiligen Detailseite aus, statt nur über die separate Interessen-
/// Einstellungsseite — nutzt dieselben Tabellen (user_favorite_persons/
/// _ensembles/_venues), damit ein Follow auf der Detailseite und eine
/// Auswahl unter Profil → Interessen konsistent denselben Zustand
/// widerspiegeln. Genres bleiben bewusst außen vor (kein Follow-Button auf
/// einer Genre-Detailseite).
@MainActor
final class FollowStore: ObservableObject {
    @Published private(set) var personIDs: Set<UUID> = []
    @Published private(set) var ensembleIDs: Set<UUID> = []
    @Published private(set) var venueIDs: Set<UUID> = []
    private let auth: AuthStore
    private let repository: UserRepository?

    init(auth: AuthStore, repository: UserRepository?) { self.auth = auth; self.repository = repository }

    var isSignedIn: Bool { auth.userID != nil }

    func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        async let persons = try? repository.selectedInterests(.person, userID: userID, token: token)
        async let ensembles = try? repository.selectedInterests(.ensemble, userID: userID, token: token)
        async let venues = try? repository.selectedInterests(.venue, userID: userID, token: token)
        personIDs = Set(((await persons) ?? []).compactMap(UUID.init(uuidString:)))
        ensembleIDs = Set(((await ensembles) ?? []).compactMap(UUID.init(uuidString:)))
        venueIDs = Set(((await venues) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func isFollowing(kind: EntityKind, id: UUID) -> Bool {
        switch kind {
        case .person: personIDs.contains(id)
        case .ensemble: ensembleIDs.contains(id)
        case .venue: venueIDs.contains(id)
        case .work: false
        }
    }

    func toggle(kind: EntityKind, id: UUID) async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        let category: InterestCategory
        switch kind {
        case .person: category = .person
        case .ensemble: category = .ensemble
        case .venue: category = .venue
        case .work: return
        }
        let newValue = !isFollowing(kind: kind, id: id)
        setLocal(kind: kind, id: id, following: newValue)
        do {
            try await repository.setInterest(category, id: id.uuidString, selected: newValue, userID: userID, token: token)
        } catch {
            setLocal(kind: kind, id: id, following: !newValue)
        }
    }

    private func setLocal(kind: EntityKind, id: UUID, following: Bool) {
        switch kind {
        case .person: if following { personIDs.insert(id) } else { personIDs.remove(id) }
        case .ensemble: if following { ensembleIDs.insert(id) } else { ensembleIDs.remove(id) }
        case .venue: if following { venueIDs.insert(id) } else { venueIDs.remove(id) }
        case .work: break
        }
    }
}
