import Foundation

struct NotificationPreferences: Sendable {
    var newMatchingEvents = true
    var priceChanges = true
    var almostSoldOut = true
    var reminderDayBefore = true
    var followedEnsembleNewEvent = true
}

enum InterestCategory: String, CaseIterable, Sendable {
    case genre, work, person, ensemble, venue
    var title: String { switch self { case .genre: "Genres"; case .work: "Werke"; case .person: "Personen"; case .ensemble: "Ensembles"; case .venue: "Orte" } }
    var systemImage: String { switch self { case .genre: "music.quarternote.3"; case .work: "music.note.list"; case .person: "person"; case .ensemble: "person.3"; case .venue: "building.columns" } }
}
struct InterestOption: Identifiable, Hashable, Sendable { let id: String; let label: String }

struct UserEventList: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date?
    let events: [ConcertEvent]
}

struct KlangradarUserProfile: Sendable {
    var displayName: String
    var birthDate: Date?
    var avatarURL: URL?
    var firstName: String?
    var lastName: String?
    var phone: String?
    var address: String?
}

struct RegionOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    var latitude: Double? = nil
    var longitude: Double? = nil
}

struct UserRepository: Sendable {
    let client: SupabaseRESTClient

    func profile(userID: UUID, token: String) async throws -> KlangradarUserProfile {
        let rows: [JSONObject] = try await client.get(
            table: "profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "display_name,birth_date,avatar_url,first_name,last_name,phone,address"),
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: token
        )
        let row = rows.first ?? [:]
        return KlangradarUserProfile(
            displayName: row.string("display_name") ?? "",
            birthDate: row.string("birth_date").flatMap(FlexibleDateParser.date(from:)),
            avatarURL: row.string("avatar_url").flatMap(URL.init(string:)),
            firstName: row.string("first_name"),
            lastName: row.string("last_name"),
            phone: row.string("phone"),
            address: row.string("address")
        )
    }

    /// Onboarding-Schritt "Persönliche Daten" — separat von `updateProfile`
    /// (das bleibt für die bestehende Profil-Bearbeitung unverändert), da
    /// Vor-/Nachname dort getrennt erfasst werden, `display_name` aber für
    /// bestehende Anzeigen weiter als kombinierter Name gepflegt wird.
    func updatePersonalData(
        firstName: String,
        lastName: String,
        userID: UUID,
        token: String
    ) async throws {
        let cleanFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFirst.isEmpty else { return }
        let displayName = cleanLast.isEmpty ? cleanFirst : "\(cleanFirst) \(cleanLast)"
        try await client.update(
            table: "profiles",
            values: [
                "first_name": .string(cleanFirst),
                "last_name": .string(cleanLast),
                "display_name": .string(displayName)
            ],
            filters: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            accessToken: token
        )
    }

    func acceptTerms(version: String, marketingEmailOptIn: Bool, userID: UUID, token: String) async throws {
        try await client.update(
            table: "profiles",
            values: [
                "terms_accepted_at": .string(ISO8601DateFormatter().string(from: .now)),
                "terms_version": .string(version),
                "marketing_email_opt_in": .bool(marketingEmailOptIn)
            ],
            filters: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            accessToken: token
        )
    }

    /// `update_home_location` ist eine `returns void`-SQL-Funktion
    /// (20260724000001_update_home_location.sql) — PostgREST liefert dafür
    /// den JSON-Wert `null`, den `JSONValue` direkt dekodieren kann.
    func updateHomeLocation(latitude: Double, longitude: Double, token: String) async throws {
        let _: JSONValue = try await client.rpc(
            "update_home_location",
            parameters: ["p_lat": .number(latitude), "p_lng": .number(longitude)],
            accessToken: token
        )
    }

    /// Seit der Stadt-Erweiterung (Berlin/Hamburg/Frankfurt/Wien neben
    /// München, siehe docs/12-city-expansion-import.md) können hier mehrere
    /// aktive Städte zurückkommen -- Grundlage für den manuellen
    /// Standort-Fallback im Onboarding UND für CityStore/CitySwitcherView.
    /// latitude/longitude (20261031000001_city_model_regions_extension.sql)
    /// werden für die "Stadt anhand meines Standorts empfehlen"-Funktion
    /// mitgeladen.
    func activeRegions() async throws -> [RegionOption] {
        let rows: [JSONObject] = try await client.get(table: "regions", queryItems: [
            URLQueryItem(name: "select", value: "id,name,latitude,longitude"),
            URLQueryItem(name: "type", value: "eq.city"),
            URLQueryItem(name: "is_active", value: "eq.true"),
            URLQueryItem(name: "order", value: "name.asc")
        ])
        return rows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let name = row.string("name") else { return nil }
            return RegionOption(id: id, name: name, latitude: row.number("latitude"), longitude: row.number("longitude"))
        }
    }

    func setPreferredRegion(regionID: UUID, userID: UUID, token: String) async throws {
        try await client.update(
            table: "profiles",
            values: ["preferred_region_id": .string(regionID.uuidString)],
            filters: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            accessToken: token
        )
    }

    /// Für CityStore: die zuletzt gewählte/gespeicherte Stadt eines
    /// angemeldeten Nutzers, um die Sitzungsauswahl beim nächsten Start
    /// vorzubelegen (siehe setPreferredRegion).
    func preferredRegionID(userID: UUID, token: String) async throws -> UUID? {
        let rows: [JSONObject] = try await client.get(
            table: "profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "preferred_region_id"),
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: token
        )
        return rows.first?.string("preferred_region_id").flatMap(UUID.init(uuidString:))
    }

    func isOnboardingCompleted(userID: UUID, token: String) async throws -> Bool {
        let rows: [JSONObject] = try await client.get(
            table: "profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "onboarding_completed"),
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: token
        )
        return rows.first?.bool("onboarding_completed") ?? false
    }

    func markOnboardingCompleted(userID: UUID, token: String) async throws {
        try await client.update(
            table: "profiles",
            values: ["onboarding_completed": .bool(true)],
            filters: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            accessToken: token
        )
    }

    func updateProfile(
        displayName: String,
        birthDate: Date?,
        userID: UUID,
        token: String
    ) async throws {
        let cleanName = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !cleanName.isEmpty else { return }
        let dateValue: JSONValue = birthDate.map {
            .string(KlangradarDateTime.string($0, format: "yyyy-MM-dd"))
        } ?? .null
        try await client.update(
            table: "profiles",
            values: ["display_name": .string(cleanName), "birth_date": dateValue],
            filters: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            accessToken: token
        )
    }

    func profileAvatarURL(userID: UUID, token: String) async throws -> URL? {
        let rows: [JSONObject] = try await client.get(
            table: "profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "avatar_url"),
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: token
        )
        return rows.first?.string("avatar_url").flatMap(URL.init(string:))
    }

    func uploadProfileAvatar(
        _ data: Data,
        userID: UUID,
        token: String
    ) async throws -> URL {
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        let publicURL = try await client.uploadPublicObject(
            bucket: "profile-avatars",
            path: path,
            data: data,
            contentType: "image/jpeg",
            accessToken: token
        )
        var components = URLComponents(url: publicURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))]
        let versionedURL = components?.url ?? publicURL
        try await client.update(
            table: "profiles",
            values: ["avatar_url": .string(versionedURL.absoluteString)],
            filters: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            accessToken: token
        )
        return versionedURL
    }

    func deleteProfileAvatar(userID: UUID, token: String) async throws {
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        try await client.deleteStorageObject(
            bucket: "profile-avatars",
            path: path,
            accessToken: token
        )
        try await client.update(
            table: "profiles",
            values: ["avatar_url": .null],
            filters: [URLQueryItem(name: "id", value: "eq.\(userID.uuidString)")],
            accessToken: token
        )
    }

    func favoriteEvents(userID: UUID, token: String) async throws -> [ConcertEvent] {
        let rows: [JSONObject] = try await client.get(table: "favorites", queryItems: [
            URLQueryItem(
                name: "select",
                value: "events(id,slug,title,subtitle,start_datetime,image_urls,status,category,is_free,venues(id,name,photo_url),event_genres(genres(id,slug,label_de)),event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url)))"
            ),
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

    /// Nutzeranfrage: Fehlermeldungen auch aus der nativen App möglich machen,
    /// analog zu Flutters ReportContentSheet (app/lib/core/widgets/
    /// report_content_sheet.dart). Schreibt in dieselbe content_reports-
    /// Tabelle; die platform-Spalte (Migration 20261011000006) unterscheidet
    /// in der Redaktion zwischen Flutter- und Native-Meldungen.
    func reportContent(
        entityType: String,
        entityID: String,
        reason: String,
        message: String?,
        userID: UUID?,
        token: String
    ) async throws {
        var values: JSONObject = [
            "entity_type": .string(entityType),
            "entity_id": .string(entityID),
            "reason": .string(reason),
            "platform": .string("native")
        ]
        values["reporter_id"] = userID.map { .string($0.uuidString) } ?? .null
        if let message, !message.isEmpty { values["message"] = .string(message) }
        _ = try await client.insert(table: "content_reports", values: values, accessToken: token)
    }

    func interestOptions(_ category: InterestCategory) async throws -> [InterestOption] {
        let specification: (String, String, String)
        switch category {
        case .genre: specification = ("genres", "id,label_de", "sort_order")
        case .work: specification = ("works", "id,title,composer:persons(full_name)", "title")
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
        return rows.compactMap { row in
            guard let id = row.string("id"),
                  let baseLabel = row.string("label_de") ?? row.string("title") ?? row.string("full_name") ?? row.string("name")
            else { return nil }
            let label: String
            if category == .work, let composer = row.object("composer")?.string("full_name") {
                label = "\(baseLabel) — \(composer)"
            } else {
                label = baseLabel
            }
            return InterestOption(id: id, label: label)
        }
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
        switch category { case .genre: ("profile_interest_genres", "genre_id"); case .work: ("user_favorite_works", "work_id"); case .person: ("user_favorite_persons", "person_id"); case .ensemble: ("user_favorite_ensembles", "ensemble_id"); case .venue: ("user_favorite_venues", "venue_id") }
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

/// App-weit als EnvironmentObject verfügbar (siehe RootTabView), damit
/// ReportContentLink auf Detailseiten (Event/Person/Ensemble/Venue) nicht
/// auth/UserRepository durch jede Zwischenansicht (SearchView, VenueMapView
/// etc.) durchreichen muss.
@MainActor
final class ReportStore: ObservableObject {
    let auth: AuthStore
    let repository: UserRepository?

    init(auth: AuthStore, repository: UserRepository?) {
        self.auth = auth
        self.repository = repository
    }
}
