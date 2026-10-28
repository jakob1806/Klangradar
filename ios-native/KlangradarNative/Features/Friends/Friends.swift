import SwiftUI

/// "Mit Freunden" (Migration 000027): Freundschaft per Code, Freunde sehen
/// gegenseitig nur, zu welchen kommenden Konzerten man "hingeht".
struct Friend: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    let upcomingCount: Int
    /// Freunde-Ausbau (000129): enge Freunde, Stummschaltung, Sortierung.
    var isClose = false
    var isMuted = false
    var nextConcert: Date? = nil
    var lastActive: Date? = nil
}

struct FriendEvent: Identifiable, Sendable, Hashable {
    let id: UUID
    let slug: String
    let title: String
    let start: Date?
    let venue: String?
    let friendNames: [String]
}

enum AddFriendResult: Sendable {
    case added(String?)
    case unknownCode
    case ownCode
}

extension UserRepository {
    func myFriendCode(token: String) async throws -> String {
        let value: JSONValue = try await client.rpc("my_friend_code", accessToken: token)
        guard case let .string(code) = value else { throw APIError.httpStatus(500, "Kein Freundescode") }
        return code
    }

    func addFriend(code: String, token: String) async throws -> AddFriendResult {
        let result: JSONObject = try await client.rpc("add_friend_by_code", parameters: ["p_code": .string(code)], accessToken: token)
        if result.bool("ok") == true { return .added(result.string("display_name")) }
        return result.string("reason") == "own_code" ? .ownCode : .unknownCode
    }

    func removeFriend(_ id: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("remove_friend", parameters: ["p_friend_id": .string(id.uuidString)], accessToken: token)
    }

    func friends(token: String) async throws -> [Friend] {
        let rows: [JSONObject] = try await client.rpc("my_friends", accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("friend_id").flatMap(UUID.init(uuidString:)) else { return nil }
            return Friend(id: id, name: row.string("display_name") ?? "Klangradar-Freund:in", avatarURL: row.string("avatar_url").flatMap(URL.init(string:)), upcomingCount: row.integer("upcoming_count") ?? 0,
                          isClose: row.bool("is_close") ?? false, isMuted: row.bool("is_muted") ?? false,
                          nextConcert: row.date("next_concert"), lastActive: row.date("last_active"))
        }
    }

    func friendsUpcomingEvents(token: String) async throws -> [FriendEvent] {
        let rows: [JSONObject] = try await client.rpc("friends_upcoming_events", accessToken: token)
        return rows.compactMap(Self.friendEvent(from:))
    }

    func friendsAttending(eventID: UUID, token: String) async throws -> [Friend] {
        let rows: [JSONObject] = try await client.rpc("friends_attending", parameters: ["p_event_id": .string(eventID.uuidString)], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("friend_id").flatMap(UUID.init(uuidString:)) else { return nil }
            return Friend(id: id, name: row.string("display_name") ?? "Freund:in", avatarURL: row.string("avatar_url").flatMap(URL.init(string:)), upcomingCount: 0)
        }
    }

    private static func friendEvent(from row: JSONObject) -> FriendEvent? {
        guard let id = row.string("event_id").flatMap(UUID.init(uuidString:)), let slug = row.string("slug"), let title = row.string("title") else { return nil }
        return FriendEvent(id: id, slug: slug, title: title, start: row.string("start_datetime").flatMap(FlexibleDateParser.date(from:)), venue: row.string("venue_name"), friendNames: row.strings("friend_names"))
    }
}
