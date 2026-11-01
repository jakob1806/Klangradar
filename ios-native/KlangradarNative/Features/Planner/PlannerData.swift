// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Abos/Zyklen,
// Saisonplaner und Konzerttagebuch. Datenzugriff über den gemeinsamen
// Supabase-Client aus SocialStore (wie PrepareSection/EventRatingSection).
import Foundation

struct ConcertSubscription: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let organizerName: String
    let season: String
    let url: URL?
    /// Redaktionell gesetztes Titelbild (Admin → Abos), sonst nil.
    var imageURL: URL? = nil

    init?(_ row: JSONObject) {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let name = row.string("name") else { return nil }
        self.id = id
        self.name = name
        organizerName = row.string("organizer_name") ?? ""
        season = row.string("season") ?? ""
        url = row.string("url").flatMap(URL.init(string:))
        imageURL = row.string("image_url").flatMap(URL.init(string:))
    }

    var title: String { "\(name) · \(organizerName)" }
}

/// Eintrag der Abo-Übersicht ("Abos entdecken", RPC subscriptions_catalog).
struct SubscriptionCatalogEntry: Identifiable, Hashable, Sendable {
    let subscription: ConcertSubscription
    let organizer: String
    let upcoming: Int
    let nextStart: Date?
    let lastStart: Date?
    let imageURL: URL?
    let venueName: String?
    var isMine: Bool
    var id: UUID { subscription.id }

    init?(_ row: JSONObject) {
        var normalized = row
        normalized["id"] = row["subscription_id"]
        guard let subscription = ConcertSubscription(normalized) else { return nil }
        self.subscription = subscription
        organizer = row.string("organizer") ?? ""
        upcoming = row.integer("upcoming") ?? 0
        nextStart = row.string("next_start").flatMap(Self.parse)
        lastStart = row.string("last_start").flatMap(Self.parse)
        imageURL = row.string("image_url").flatMap(URL.init(string:))
        venueName = row.string("venue_name")
        isMine = row.bool("is_mine") ?? false
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct SubscriptionSuggestion: Identifiable, Hashable, Sendable {
    let subscription: ConcertSubscription
    let matched: Int
    let total: Int
    var id: UUID { subscription.id }
}

struct DiaryEntry: Sendable, Equatable {
    var note = ""
    var companions = ""
    var restaurant = ""
    var otherPlaces = ""
    var photoPaths: [String] = []

    init() {}

    init(_ row: JSONObject) {
        note = row.string("note") ?? ""
        companions = row.string("companions") ?? ""
        restaurant = row.string("restaurant") ?? ""
        otherPlaces = row.string("other_places") ?? ""
        photoPaths = row.strings("photo_paths")
    }

    var isEmpty: Bool { note.isEmpty && companions.isEmpty && restaurant.isEmpty && otherPlaces.isEmpty && photoPaths.isEmpty }
}

@MainActor
enum PlannerAPI {
    private static var client: SupabaseRESTClient? { SocialStore.shared.repository?.client }
    private static var token: String? { SocialStore.shared.token }
    static var userID: UUID? { SocialStore.shared.auth?.userID }

    // MARK: Glocke je Gefolgtem (Mitteilungs-Konzept 01.11.2026)

    private static func followTable(_ kind: String) -> (table: String, column: String)? {
        switch kind {
        case "person": ("user_favorite_persons", "person_id")
        case "ensemble": ("user_favorite_ensembles", "ensemble_id")
        case "venue": ("user_favorite_venues", "venue_id")
        default: nil
        }
    }

    /// Ob neue Konzerte dieser gefolgten Person/dieses Ensembles/Orts gemeldet werden.
    static func followNotifies(kind: String, id: UUID) async -> Bool {
        guard let client, let token, let userID, let t = followTable(kind) else { return true }
        let rows: [JSONObject]? = try? await client.get(table: t.table, queryItems: [
            URLQueryItem(name: "select", value: "notify_new_events"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: t.column, value: "eq.\(id.uuidString)")
        ], accessToken: token)
        return rows?.first?.bool("notify_new_events") ?? true
    }

    static func setFollowNotifies(kind: String, id: UUID, _ enabled: Bool) async {
        guard let client, let token, let userID, let t = followTable(kind) else { return }
        try? await client.update(table: t.table, values: ["notify_new_events": .bool(enabled)], filters: [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: t.column, value: "eq.\(id.uuidString)")
        ], accessToken: token)
    }

    // MARK: Abos

    static func subscriptions(eventID: UUID) async -> [ConcertSubscription] {
        guard let client else { return [] }
        let rows: [JSONObject]? = try? await client.get(table: "event_concert_subscriptions", queryItems: [
            URLQueryItem(name: "select", value: "concert_subscriptions(id,name,organizer_name,season,url)"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)")
        ])
        return (rows ?? []).compactMap { $0.object("concert_subscriptions").flatMap(ConcertSubscription.init) }
    }

    /// Termine eines Abos (IDs in Konzertreihenfolge) und ob es "meins" ist.
    static func overview(_ id: UUID) async -> (eventIDs: [UUID], isMine: Bool)? {
        guard let client else { return nil }
        let row: JSONObject? = try? await client.rpc("subscription_overview", parameters: ["p_subscription_id": .string(id.uuidString)], accessToken: token)
        guard let row else { return nil }
        let ids = row.objects("events").compactMap { $0.string("id").flatMap(UUID.init(uuidString:)) }
        return (ids, row.bool("is_mine") ?? false)
    }

    /// Für Seiten ohne eigenes EventRepository (Ensembleseite).
    static var eventRepository: (any EventRepository)? { client.map { LiveEventRepository(client: $0) } }

    /// Abos, in denen ein Ensemble regelmäßig spielt (RPC ensemble_subscriptions).
    static func ensembleSubscriptions(ensembleID: String) async -> [SubscriptionCatalogEntry] {
        guard let client, UUID(uuidString: ensembleID) != nil else { return [] }
        let rows: [JSONObject]? = try? await client.rpc("ensemble_subscriptions", parameters: ["p_ensemble_id": .string(ensembleID)], accessToken: token)
        return (rows ?? []).compactMap(SubscriptionCatalogEntry.init)
    }

    /// Alle Abos mit kommenden Terminen, optional für eine Stadt.
    static func catalog(cityID: UUID?) async -> [SubscriptionCatalogEntry] {
        guard let client else { return [] }
        let parameters: [String: JSONValue] = ["p_city_id": cityID.map { .string($0.uuidString) } ?? .null]
        let rows: [JSONObject]? = try? await client.rpc("subscriptions_catalog", parameters: parameters, accessToken: token)
        return (rows ?? []).compactMap(SubscriptionCatalogEntry.init)
    }

    static func mySubscriptions() async -> [ConcertSubscription] {
        guard let client, let token, let userID else { return [] }
        let rows: [JSONObject]? = try? await client.get(table: "user_concert_subscriptions", queryItems: [
            URLQueryItem(name: "select", value: "concert_subscriptions(id,name,organizer_name,season,url)"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ], accessToken: token)
        return (rows ?? []).compactMap { $0.object("concert_subscriptions").flatMap(ConcertSubscription.init) }
    }

    /// Gewählte Abo-Variante je Abo (ISO-Wochentag, 1 = Mo … 7 = So), z. B.
    /// Donnerstag- oder Freitag-Reihe beim BRSO (Nutzerwunsch 01.11.2026).
    static func myVariants() async -> [UUID: Int] {
        guard let client, let token, let userID else { return [:] }
        let rows: [JSONObject]? = try? await client.get(table: "user_concert_subscriptions", queryItems: [
            URLQueryItem(name: "select", value: "subscription_id,weekday"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ], accessToken: token)
        var result: [UUID: Int] = [:]
        for row in rows ?? [] {
            if let id = row.string("subscription_id").flatMap(UUID.init(uuidString:)), let weekday = row.integer("weekday") {
                result[id] = weekday
            }
        }
        return result
    }

    /// Eigener Platz je Abo ("Parkett links, Reihe 12, Platz 7"), Nutzerwunsch
    /// 01.11.2026: steht dann bei jedem Konzert des Abos.
    static func mySeats() async -> [UUID: String] {
        guard let client, let token, let userID else { return [:] }
        let rows: [JSONObject]? = try? await client.get(table: "user_concert_subscriptions", queryItems: [
            URLQueryItem(name: "select", value: "subscription_id,seat"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "seat", value: "not.is.null")
        ], accessToken: token)
        var result: [UUID: String] = [:]
        for row in rows ?? [] {
            if let id = row.string("subscription_id").flatMap(UUID.init(uuidString:)), let seat = row.string("seat"), !seat.isEmpty {
                result[id] = seat
            }
        }
        return result
    }

    static func setSeat(_ subscriptionID: UUID, _ seat: String) async throws {
        guard let client, let token, let userID else { return }
        let trimmed = String(seat.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        try await client.update(table: "user_concert_subscriptions", values: [
            "seat": trimmed.isEmpty ? .null : .string(trimmed)
        ], filters: [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "subscription_id", value: "eq.\(subscriptionID.uuidString)")
        ], accessToken: token)
    }

    /// Erinnerung am Konzerttag je eigenem Abo (Server, Standard an).
    static func myReminders() async -> [UUID: Bool] {
        guard let client, let token, let userID else { return [:] }
        let rows: [JSONObject]? = try? await client.get(table: "user_concert_subscriptions", queryItems: [
            URLQueryItem(name: "select", value: "subscription_id,remind"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ], accessToken: token)
        var result: [UUID: Bool] = [:]
        for row in rows ?? [] {
            if let id = row.string("subscription_id").flatMap(UUID.init(uuidString:)) { result[id] = row.bool("remind") ?? true }
        }
        return result
    }

    static func setReminder(_ subscriptionID: UUID, _ enabled: Bool) async throws {
        guard let client, let token, let userID else { return }
        try await client.update(table: "user_concert_subscriptions", values: ["remind": .bool(enabled)], filters: [
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "subscription_id", value: "eq.\(subscriptionID.uuidString)")
        ], accessToken: token)
    }

    /// Termine (mit Beginn) aller eigenen Abos außer `excluding` – für den
    /// Hinweis auf Überschneidungen zwischen zwei Abos am selben Tag.
    static func otherSubscriptionDates(excluding subscriptionID: UUID) async -> [(date: Date, subscription: ConcertSubscription)] {
        guard let client else { return [] }
        let mine = await mySubscriptions().filter { $0.id != subscriptionID }
        guard !mine.isEmpty else { return [] }
        let variants = await myVariants()
        let rows: [JSONObject]? = try? await client.get(table: "event_concert_subscriptions", queryItems: [
            URLQueryItem(name: "select", value: "subscription_id,events(start_datetime)"),
            URLQueryItem(name: "subscription_id", value: "in.(\(mine.map(\.id.uuidString).joined(separator: ",")))")
        ])
        let byID = Dictionary(uniqueKeysWithValues: mine.map { ($0.id, $0) })
        return (rows ?? []).compactMap { row in
            guard let sub = row.string("subscription_id").flatMap(UUID.init(uuidString:)).flatMap({ byID[$0] }),
                  let start = row.object("events")?.string("start_datetime").flatMap(FlexibleDateParser.date(from:)) else { return nil }
            if let weekday = variants[sub.id], SubscriptionVariant.isoWeekday(start) != weekday { return nil }
            return (start, sub)
        }
    }

    static func setMine(_ subscriptionID: UUID, _ isMine: Bool, weekday: Int? = nil) async throws {
        guard let client, let token, let userID else { return }
        if isMine {
            try await client.upsert(table: "user_concert_subscriptions", values: [
                "user_id": .string(userID.uuidString), "subscription_id": .string(subscriptionID.uuidString),
                "weekday": weekday.map { .number(Double($0)) } ?? .null
            ], accessToken: token, conflictColumns: "user_id,subscription_id")
        } else {
            try await client.delete(table: "user_concert_subscriptions", filters: [
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "subscription_id", value: "eq.\(subscriptionID.uuidString)")
            ], accessToken: token)
        }
    }

    static func suggestions() async -> [SubscriptionSuggestion] {
        guard let client, let token else { return [] }
        let rows: [JSONObject]? = try? await client.rpc("suggested_subscriptions", accessToken: token)
        return (rows ?? []).compactMap { row in
            var normalized = row
            normalized["id"] = row["subscription_id"]
            guard let subscription = ConcertSubscription(normalized) else { return nil }
            return SubscriptionSuggestion(subscription: subscription, matched: row.integer("matched") ?? 0, total: row.integer("total") ?? 0)
        }
    }

    /// Alle kommenden Termine der eigenen Abos (für den Saisonplaner).
    static func subscriptionEventIDs() async -> [UUID: [ConcertSubscription]] {
        guard let client else { return [:] }
        let mine = await mySubscriptions()
        guard !mine.isEmpty else { return [:] }
        let variants = await myVariants()
        let rows: [JSONObject]? = try? await client.get(table: "event_concert_subscriptions", queryItems: [
            URLQueryItem(name: "select", value: "event_id,subscription_id,events(start_datetime)"),
            URLQueryItem(name: "subscription_id", value: "in.(\(mine.map(\.id.uuidString).joined(separator: ",")))")
        ])
        let byID = Dictionary(uniqueKeysWithValues: mine.map { ($0.id, $0) })
        var result: [UUID: [ConcertSubscription]] = [:]
        for row in rows ?? [] {
            guard let event = row.string("event_id").flatMap(UUID.init(uuidString:)),
                  let sub = row.string("subscription_id").flatMap(UUID.init(uuidString:)).flatMap({ byID[$0] }) else { continue }
            // Gewählte Variante (z. B. nur Freitage): andere Wochentage weglassen.
            if let weekday = variants[sub.id],
               let start = row.object("events")?.string("start_datetime").flatMap(FlexibleDateParser.date(from:)),
               SubscriptionVariant.isoWeekday(start) != weekday { continue }
            result[event, default: []].append(sub)
        }
        return result
    }

    // MARK: Saisonplaner

    /// Geplante Besuche (event_attendance.status = planned).
    static func plannedEventIDs() async -> Set<UUID> {
        guard let client, let token, let userID else { return [] }
        let rows: [JSONObject]? = try? await client.get(table: "event_attendance", queryItems: [
            URLQueryItem(name: "select", value: "event_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "status", value: "eq.planned")
        ], accessToken: token)
        return Set((rows ?? []).compactMap { $0.string("event_id").flatMap(UUID.init(uuidString:)) })
    }

    // MARK: Tagebuch

    /// Auch vergangene Termine (events(ids:) liefert nur kommende).
    static func events(ids: [UUID]) async -> [ConcertEvent] {
        guard let client, !ids.isEmpty else { return [] }
        return (try? await client.get(table: "events", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,title,subtitle,start_datetime,venue_detail,image_urls,updated_at,status,category,is_free,price_min,discount_info,venues(id,name,photo_url,city_id),event_genres(genres(id,slug,label_de)),event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url))"),
            URLQueryItem(name: "id", value: "in.(\(ids.map(\.uuidString).joined(separator: ",")))")
        ])) ?? []
    }

    static func diaryEntry(eventID: UUID) async -> DiaryEntry? {
        guard let client, let token, let userID else { return nil }
        let rows: [JSONObject]? = try? await client.get(table: "concert_diary_entries", queryItems: [
            URLQueryItem(name: "select", value: "note,companions,restaurant,other_places,photo_paths"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)")
        ], accessToken: token)
        return rows?.first.map(DiaryEntry.init)
    }

    /// event_id → Eintrag, neueste zuerst.
    static func diaryEntries() async -> [(eventID: UUID, entry: DiaryEntry)] {
        guard let client, let token, let userID else { return [] }
        let rows: [JSONObject]? = try? await client.get(table: "concert_diary_entries", queryItems: [
            URLQueryItem(name: "select", value: "event_id,note,companions,restaurant,other_places,photo_paths"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "order", value: "updated_at.desc")
        ], accessToken: token)
        return (rows ?? []).compactMap { row in
            row.string("event_id").flatMap(UUID.init(uuidString:)).map { ($0, DiaryEntry(row)) }
        }
    }

    static func saveDiary(_ entry: DiaryEntry, eventID: UUID) async throws {
        guard let client, let token, let userID else { return }
        func text(_ value: String) -> JSONValue { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .null : .string(value) }
        try await client.upsert(table: "concert_diary_entries", values: [
            "user_id": .string(userID.uuidString),
            "event_id": .string(eventID.uuidString),
            "note": text(entry.note),
            "companions": text(entry.companions),
            "restaurant": text(entry.restaurant),
            "other_places": text(entry.otherPlaces),
            "photo_paths": .array(entry.photoPaths.map { .string($0) }),
            "updated_at": .string(ISO8601DateFormatter().string(from: .now))
        ], accessToken: token, conflictColumns: "user_id,event_id")
    }

    static func uploadDiaryPhoto(_ data: Data, eventID: UUID) async throws -> String? {
        guard let client, let token, let userID else { return nil }
        let path = "\(userID.uuidString.lowercased())/\(eventID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.uploadPublicObject(bucket: "diary-photos", path: path, data: data, contentType: "image/jpeg", accessToken: token)
        return path
    }

    static func deleteDiaryPhoto(_ path: String) async {
        guard let client, let token else { return }
        try? await client.deleteStorageObject(bucket: "diary-photos", path: path, accessToken: token)
    }

    /// Privater Bucket: Fotos nur über signierte, kurzlebige URLs.
    static func signedPhotoURL(_ path: String) async -> URL? {
        guard let client, let token else { return nil }
        return try? await client.signedStorageURL(bucket: "diary-photos", path: path, expiresIn: 3600, accessToken: token)
    }
}

extension Locale {
    /// Klangradar ist deutschsprachig: Monats-/Wochentagsnamen immer deutsch,
    /// auch wenn das iPhone auf Englisch steht (Nutzermeldung 27.10.2026).
    static let klangradarGerman = Locale(identifier: "de_DE")
}
