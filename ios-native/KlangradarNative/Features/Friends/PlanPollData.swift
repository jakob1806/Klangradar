// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 9, 10, 12).
import Foundation

struct PlanPollOption: Identifiable, Sendable, Hashable {
    var id: UUID { event.id }
    let event: SocialEvent
    let votes: Int
    let mine: Bool
}

struct FriendTasteMatch: Identifiable, Sendable, Hashable {
    var id: UUID { person.id }
    let person: SocialPerson
    let reason: String
}

struct ConcertYear: Sendable {
    let year: Int
    let concerts: Int
    let minutes: Int
    let venues: Int
    let topComposers: [(name: String, count: Int)]
    let topVenue: String?
    let topArtist: String?
    let bestRated: (title: String, stars: Int)?
    let first: String?
    // Ab Migration 20261231000126 (ältere Server liefern sie nicht: leer/0).
    var cities = 0
    var works = 0
    /// 12 Werte, Januar … Dezember.
    var months: [Int] = []
    /// 7 Werte, Montag … Sonntag.
    var weekdays: [Int] = []
    var topVenues: [(name: String, count: Int)] = []
    var topArtists: [(name: String, count: Int)] = []
}

extension UserRepository {
    @discardableResult
    func createPlanPoll(eventIDs: [UUID], friendIDs: [UUID], note: String?, token: String) async throws -> UUID? {
        let value: JSONValue = try await client.rpc("create_plan_poll", parameters: [
            "p_event_ids": .array(eventIDs.map { .string($0.uuidString) }),
            "p_friend_ids": .array(friendIDs.map { .string($0.uuidString) }),
            "p_note": note.map(JSONValue.string) ?? .null
        ], accessToken: token)
        if case let .string(id) = value { return UUID(uuidString: id) }
        return nil
    }

    func planPoll(_ planID: UUID, token: String) async throws -> [PlanPollOption] {
        let value: JSONValue = try await client.rpc("plan_poll", parameters: ["p_plan_id": .string(planID.uuidString)], accessToken: token)
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item in
            guard case let .object(row) = item, let event = row.socialEvent() else { return nil }
            return PlanPollOption(event: event, votes: row.integer("votes") ?? 0, mine: row.bool("mine") ?? false)
        }
    }

    func votePlanOption(_ planID: UUID, eventID: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("vote_plan_option", parameters: ["p_plan_id": .string(planID.uuidString), "p_event_id": .string(eventID.uuidString)], accessToken: token)
    }

    func decidePlanPoll(_ planID: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("decide_plan_poll", parameters: ["p_plan_id": .string(planID.uuidString), "p_force": .bool(true)], accessToken: token)
    }

    func friendTaste(eventID: UUID, token: String) async throws -> [FriendTasteMatch] {
        let rows: [JSONObject] = try await client.rpc("friend_taste_for_event", parameters: ["p_event_id": .string(eventID.uuidString)], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.uuid("user_id"), let reason = row.string("reason") else { return nil }
            return FriendTasteMatch(person: SocialPerson(id: id, name: row.string("display_name") ?? "Freund:in", avatarURL: row.string("avatar_url").flatMap(URL.init(string:))), reason: reason)
        }
    }

    private static func int(_ value: JSONValue) -> Int {
        if case let .number(number) = value { return Int(number) }
        return 0
    }

    func concertYear(_ year: Int? = nil, token: String) async throws -> ConcertYear {
        let row: JSONObject = try await client.rpc("my_concert_year", parameters: ["p_year": year.map { .number(Double($0)) } ?? .null], accessToken: token)
        let best = row.object("best_rated")
        return ConcertYear(
            year: row.integer("year") ?? Calendar.current.component(.year, from: .now),
            concerts: row.integer("concerts") ?? 0,
            minutes: row.integer("minutes") ?? 0,
            venues: row.integer("venues") ?? 0,
            topComposers: row.objects("top_composers").compactMap { item in item.string("name").map { ($0, item.integer("count") ?? 0) } },
            topVenue: row.string("top_venue"),
            topArtist: row.string("top_artist"),
            bestRated: best.flatMap { item in item.string("title").map { ($0, item.integer("stars") ?? 0) } },
            first: row.object("first")?.string("title"),
            cities: row.integer("cities") ?? 0,
            works: row.integer("works") ?? 0,
            months: row.array("months").map(Self.int),
            weekdays: row.array("weekdays").map(Self.int),
            topVenues: row.objects("top_venues").compactMap { item in item.string("name").map { ($0, item.integer("count") ?? 0) } },
            topArtists: row.objects("top_artists").compactMap { item in item.string("name").map { ($0, item.integer("count") ?? 0) } }
        )
    }
}
