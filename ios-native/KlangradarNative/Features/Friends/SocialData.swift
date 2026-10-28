import CryptoKit
import Foundation

// Social-Ausbau (Migration 000096): Modelle, RPC-Aufrufe und der zentrale
// SocialStore, den Home, Konzertseite, Profil und Freunde-Bereich teilen.

enum RelationStatus: String, Sendable {
    case none, requested, incoming, friend, blocked
    init(_ raw: String?) { self = RelationStatus(rawValue: raw ?? "") ?? .none }
}

struct SocialPerson: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    var detail: String? = nil
    var status: RelationStatus = .none
}

struct FriendRequest: Identifiable, Sendable, Hashable {
    var id: UUID { person.id }
    let person: SocialPerson
    let incoming: Bool
    let mutualFriends: Int
    /// Freunde-Ausbau (000129): Quelle, Konzert und gemeinsame Komponist:innen.
    var source: String? = nil
    var sharedComposers: [String] = []
    var context: String? = nil
}

struct ActivityItem: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable { case attending, attended, rated }
    let id = UUID()
    let kind: Kind
    let person: SocialPerson
    let event: SocialEvent
    let stars: Int?
    let comment: String?
    let happenedAt: Date?
}

struct SocialEvent: Identifiable, Sendable, Hashable {
    let id: UUID
    let slug: String
    let title: String
    let start: Date?
    let venue: String?
    let imageURL: URL?
    var note: String? = nil

    var dateLine: String {
        [start.map { KlangradarDateTime.string($0, format: "EEE, d. MMM · HH:mm") }, venue].compactMap { $0 }.joined(separator: " · ")
    }
}

struct PlanMember: Identifiable, Sendable, Hashable {
    var id: UUID { person.id }
    let person: SocialPerson
    let status: String
}

struct ConcertPlan: Identifiable, Sendable, Hashable {
    let id: UUID
    let event: SocialEvent
    let meetingPoint: String?
    let meetingTime: Date?
    let note: String?
    let isOwner: Bool
    let myStatus: String
    let members: [PlanMember]

    var going: [PlanMember] { members.filter { $0.status == "going" } }
    var hasMeeting: Bool { meetingPoint != nil || meetingTime != nil }
}

struct UserProfile: Sendable {
    let person: SocialPerson
    let bio: String?
    let visible: Bool
    let isFriend: Bool
    let concerts: Int
    let friends: Int
    let mutualFriends: Int
    let topComposers: [String]
    let upcoming: [SocialEvent]
    /// Freunde-Ausbau (000129).
    var tasteMatch: Int? = nil
    var sharedComposers: [String] = []
    var isClose = false
    var isMuted = false
    var sharedHistory: [SocialEvent] = []
    var ratings: [ProfileRating] = []
}

struct EventRatings: Sendable {
    struct Rating: Identifiable, Sendable, Hashable {
        var id: UUID { person.id }
        let person: SocialPerson
        let stars: Int
        let comment: String?
    }
    let mine: (stars: Int, comment: String?)?
    let friends: [Rating]
}

struct SocialSettings: Sendable, Equatable {
    var bio = ""
    var isPublic = false
    var shareActivity = true
    var contactDiscoverable = false
}

struct SharedList: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let ownerName: String
    let coverURL: URL?
    let itemCount: Int
}

// MARK: - Parsing

extension JSONObject {
    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
    func url(_ key: String) -> URL? { string(key).flatMap(URL.init(string:)) }
    func date(_ key: String) -> Date? { string(key).flatMap(FlexibleDateParser.date(from:)) }

    func person(idKey: String = "user_id", detail: String? = nil) -> SocialPerson? {
        guard let id = uuid(idKey) else { return nil }
        return SocialPerson(id: id, name: string("display_name") ?? "Klangradar-Freund:in", avatarURL: url("avatar_url"), detail: detail, status: RelationStatus(string("status")))
    }

    func socialEvent() -> SocialEvent? {
        guard let id = uuid("event_id"), let slug = string("slug"), let title = string("title") else { return nil }
        return SocialEvent(id: id, slug: slug, title: title, start: date("start_datetime"), venue: string("venue_name"), imageURL: url("image_url"), note: string("reason"))
    }
}

// MARK: - RPCs

extension UserRepository {
    private func rows(_ function: String, _ parameters: JSONObject = [:], token: String) async throws -> [JSONObject] {
        try await client.rpc(function, parameters: parameters, accessToken: token)
    }

    private func call(_ function: String, _ parameters: JSONObject = [:], token: String) async throws {
        let _: JSONValue = try await client.rpc(function, parameters: parameters, accessToken: token)
    }

    func friendRequests(token: String) async throws -> [FriendRequest] {
        try await rows("my_friend_requests", token: token).compactMap { row in
            guard let person = row.person() else { return nil }
            return FriendRequest(person: person, incoming: row.bool("incoming") ?? false, mutualFriends: row.integer("mutual_friends") ?? 0,
                                 source: row.string("source"), sharedComposers: row.strings("shared_composers"), context: row.string("context"))
        }
    }

    @discardableResult
    func sendFriendRequest(to id: UUID, source: String, eventID: UUID? = nil, token: String) async throws -> RelationStatus {
        var parameters: JSONObject = ["p_user_id": .string(id.uuidString), "p_source": .string(source)]
        if let eventID { parameters["p_event_id"] = .string(eventID.uuidString) }
        let value: JSONValue = try await client.rpc("send_friend_request", parameters: parameters, accessToken: token)
        guard case let .string(result) = value else { return .requested }
        return result == "friends" || result == "already_friends" ? .friend : result == "blocked" ? .blocked : .requested
    }

    func respondFriendRequest(from id: UUID, accept: Bool, token: String) async throws {
        try await call("respond_friend_request", ["p_user_id": .string(id.uuidString), "p_accept": .bool(accept)], token: token)
    }

    func cancelFriendRequest(to id: UUID, token: String) async throws {
        try await call("cancel_friend_request", ["p_user_id": .string(id.uuidString)], token: token)
    }

    func blockUser(_ id: UUID, token: String) async throws {
        try await call("block_user", ["p_user_id": .string(id.uuidString)], token: token)
    }

    func suggestedFriends(token: String) async throws -> [SocialPerson] {
        try await rows("suggested_friends", token: token).compactMap { $0.person(detail: $0.string("reason")) }
    }

    func searchProfiles(_ query: String, token: String) async throws -> [SocialPerson] {
        try await rows("search_profiles", ["p_query": .string(query)], token: token).compactMap { $0.person(detail: $0.string("bio")) }
    }

    func matchContacts(hashes: [String], token: String) async throws -> [SocialPerson] {
        try await rows("match_contacts", ["p_hashes": .array(hashes.map(JSONValue.string))], token: token).compactMap { $0.person() }
    }

    func setContactDiscovery(_ enabled: Bool, phoneHash: String?, token: String) async throws {
        try await call("set_contact_discovery", ["p_enabled": .bool(enabled), "p_phone_hash": phoneHash.map(JSONValue.string) ?? .null], token: token)
    }

    func userProfile(_ id: UUID, token: String) async throws -> UserProfile? {
        let row: JSONObject? = try? await client.rpc("user_profile", parameters: ["p_user_id": .string(id.uuidString)], accessToken: token)
        guard let row, let person = row.person() else { return nil }
        return UserProfile(
            person: person, bio: row.string("bio"), visible: row.bool("visible") ?? false, isFriend: row.bool("is_friend") ?? false,
            concerts: row.integer("concerts") ?? 0, friends: row.integer("friends") ?? 0, mutualFriends: row.integer("mutual_friends") ?? 0,
            topComposers: row.strings("top_composers"), upcoming: row.objects("upcoming").compactMap { $0.socialEvent() },
            tasteMatch: row.integer("taste_match"), sharedComposers: row.strings("shared_composers"),
            isClose: row.bool("is_close") ?? false, isMuted: row.bool("is_muted") ?? false,
            sharedHistory: row.socialEvents("shared_history"),
            ratings: row.objects("ratings").compactMap { item in
                guard let event = item.socialEvent(), let stars = item.integer("stars") else { return nil }
                return ProfileRating(event: event, stars: stars, comment: item.string("comment"))
            }
        )
    }

    func socialSettings(token: String) async throws -> SocialSettings {
        let row: JSONObject = try await client.rpc("my_social_settings", accessToken: token)
        return SocialSettings(bio: row.string("bio") ?? "", isPublic: row.bool("is_public") ?? false, shareActivity: row.bool("share_activity") ?? true, contactDiscoverable: row.bool("contact_discoverable") ?? false)
    }

    func updateSocialSettings(_ settings: SocialSettings, token: String) async throws {
        try await call("update_social_settings", ["p_bio": .string(settings.bio), "p_is_public": .bool(settings.isPublic), "p_share_activity": .bool(settings.shareActivity)], token: token)
    }

    func friendActivity(token: String) async throws -> [ActivityItem] {
        try await rows("friend_activity", token: token).compactMap { row in
            guard let person = row.person(), let event = row.socialEvent(), let kind = ActivityItem.Kind(rawValue: row.string("kind") ?? "") else { return nil }
            return ActivityItem(kind: kind, person: person, event: event, stars: row.integer("stars"), comment: row.string("comment"), happenedAt: row.date("happened_at"))
        }
    }

    func concertPlans(token: String) async throws -> [ConcertPlan] {
        let value: JSONValue = try await client.rpc("my_concert_plans", accessToken: token)
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item -> ConcertPlan? in
            guard case let .object(row) = item, let id = row.uuid("plan_id"), let event = row.socialEvent() else { return nil }
            let members = row.objects("members").compactMap { member -> PlanMember? in
                guard let person = member.person() else { return nil }
                return PlanMember(person: person, status: member.string("status") ?? "invited")
            }
            return ConcertPlan(id: id, event: event, meetingPoint: row.string("meeting_point"), meetingTime: row.date("meeting_time"), note: row.string("note"),
                               isOwner: row.bool("is_owner") ?? false, myStatus: row.string("my_status") ?? "invited", members: members)
        }
    }

    @discardableResult
    func createConcertPlan(eventID: UUID, friendIDs: [UUID], meetingPoint: String?, meetingTime: Date?, note: String?, token: String) async throws -> UUID? {
        let value: JSONValue = try await client.rpc("create_concert_plan", parameters: [
            "p_event_id": .string(eventID.uuidString),
            "p_friend_ids": .array(friendIDs.map { .string($0.uuidString) }),
            "p_meeting_point": meetingPoint.map(JSONValue.string) ?? .null,
            "p_meeting_time": meetingTime.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "p_note": note.map(JSONValue.string) ?? .null
        ], accessToken: token)
        if case let .string(id) = value { return UUID(uuidString: id) }
        return nil
    }

    func respondConcertPlan(_ id: UUID, status: String, token: String) async throws {
        try await call("respond_concert_plan", ["p_plan_id": .string(id.uuidString), "p_status": .string(status)], token: token)
    }

    func updateConcertPlan(_ id: UUID, meetingPoint: String?, meetingTime: Date?, note: String?, token: String) async throws {
        try await call("update_concert_plan", [
            "p_plan_id": .string(id.uuidString), "p_meeting_point": meetingPoint.map(JSONValue.string) ?? .null,
            "p_meeting_time": meetingTime.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null, "p_note": note.map(JSONValue.string) ?? .null
        ], token: token)
    }

    func inviteToPlan(_ id: UUID, friendIDs: [UUID], token: String) async throws {
        try await call("invite_to_plan", ["p_plan_id": .string(id.uuidString), "p_friend_ids": .array(friendIDs.map { .string($0.uuidString) })], token: token)
    }

    func leaveConcertPlan(_ id: UUID, token: String) async throws {
        try await call("leave_concert_plan", ["p_plan_id": .string(id.uuidString)], token: token)
    }

    func friendMatchEvents(_ friendID: UUID, token: String) async throws -> [SocialEvent] {
        try await rows("friend_match_events", ["p_friend_id": .string(friendID.uuidString)], token: token).compactMap { $0.socialEvent() }
    }

    func sharedConcerts(with friendID: UUID, year: Int, token: String) async throws -> [SocialEvent] {
        try await rows("shared_concerts_with", ["p_friend_id": .string(friendID.uuidString), "p_year": .number(Double(year))], token: token).compactMap { $0.socialEvent() }
    }

    func friendsPopularEvents(token: String) async throws -> [(id: UUID, names: [String], count: Int)] {
        try await rows("friends_popular_events", token: token).compactMap { row in
            guard let id = row.uuid("event_id") else { return nil }
            return (id, row.strings("friend_names"), row.integer("friend_count") ?? 0)
        }
    }

    func eventRatings(_ eventID: UUID, token: String) async throws -> EventRatings {
        let row: JSONObject = try await client.rpc("event_ratings_summary", parameters: ["p_event_id": .string(eventID.uuidString)], accessToken: token)
        let mine = row.object("mine").flatMap { mine in mine.integer("stars").map { (stars: $0, comment: mine.string("comment")) } }
        let friends = row.objects("friends").compactMap { item -> EventRatings.Rating? in
            guard let person = item.person(), let stars = item.integer("stars") else { return nil }
            return EventRatings.Rating(person: person, stars: stars, comment: item.string("comment"))
        }
        return EventRatings(mine: mine, friends: friends)
    }

    func rateEvent(_ eventID: UUID, stars: Int, comment: String?, token: String) async throws {
        try await call("rate_event", ["p_event_id": .string(eventID.uuidString), "p_stars": .number(Double(stars)), "p_comment": comment.map(JSONValue.string) ?? .null], token: token)
    }

    func shareList(_ listID: UUID, with friendIDs: [UUID], token: String) async throws {
        try await call("share_list_with_friends", ["p_list_id": .string(listID.uuidString), "p_friend_ids": .array(friendIDs.map { .string($0.uuidString) })], token: token)
    }

    func listMembers(_ listID: UUID, token: String) async throws -> [SocialPerson] {
        try await rows("list_members", ["p_list_id": .string(listID.uuidString)], token: token).compactMap { row in
            row.person(detail: row.bool("is_owner") == true ? "Erstellt" : nil)
        }
    }

    func removeListMember(_ listID: UUID, userID: UUID, token: String) async throws {
        try await call("remove_list_member", ["p_list_id": .string(listID.uuidString), "p_user_id": .string(userID.uuidString)], token: token)
    }

    func listsSharedWithMe(token: String) async throws -> [SharedList] {
        try await rows("lists_shared_with_me", token: token).compactMap { row in
            guard let id = row.uuid("list_id") else { return nil }
            return SharedList(id: id, name: row.string("name") ?? "Liste", ownerName: row.string("owner_name") ?? "Freund:in", coverURL: row.url("cover_image_url"), itemCount: row.integer("item_count") ?? 0)
        }
    }

    /// reason: spam | inappropriate | impersonation | other
    func reportUser(_ id: UUID, reason: String, token: String) async throws {
        try await call("report_user", ["p_user_id": .string(id.uuidString), "p_reason": .string(reason)], token: token)
    }
}

// MARK: - Kontakte

enum ContactHashing {
    /// SHA-256 (hex) normalisierter Werte; Klartext verlässt das Gerät nie.
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// +49 170 1234567 / 0170-1234567 / 0049… → +491701234567 (Standard: Deutschland).
    static func normalizedPhone(_ phone: String, defaultCountryCode: String = "49") -> String? {
        var digits = phone.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("00") { digits = "+" + digits.dropFirst(2) }
        if digits.hasPrefix("0") { digits = "+\(defaultCountryCode)" + digits.dropFirst() }
        if !digits.hasPrefix("+") { digits = "+\(defaultCountryCode)" + digits }
        let numberPart = digits.dropFirst().filter(\.isNumber)
        guard numberPart.count >= 8 else { return nil }
        return "+" + numberPart
    }
}

// MARK: - Store

/// Gemeinsamer Social-Zustand: Anfragen-Zähler (Badge), Pläne, "Beliebt bei
/// Freunden" für Home. Konfiguriert in RootTabView.
@MainActor
final class SocialStore: ObservableObject {
    static let shared = SocialStore()
    @Published private(set) var incomingRequests = 0
    @Published private(set) var pendingPlanInvites = 0
    @Published private(set) var friendsPopular: [ConcertEvent] = []
    @Published private(set) var friendsPopularNames: [UUID: [String]] = [:]

    private(set) var auth: AuthStore?
    private(set) var repository: UserRepository?
    private var eventRepository: (any EventRepository)?

    var isSignedIn: Bool { auth?.userID != nil }
    var token: String? { auth?.accessToken }

    func configure(auth: AuthStore, repository: UserRepository?, eventRepository: any EventRepository) {
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
    }

    /// Volles Konzert für den Planungsdialog (z. B. "Gemeinsam planen").
    func concertEvent(_ id: UUID) async -> ConcertEvent? {
        guard let eventRepository else { return nil }
        return try? await eventRepository.events(ids: [id]).first
    }

    func refresh() async {
        guard let repository, let token else {
            incomingRequests = 0; pendingPlanInvites = 0; friendsPopular = []
            return
        }
        async let requests = try? repository.friendRequests(token: token)
        async let plans = try? repository.concertPlans(token: token)
        async let popular = try? repository.friendsPopularEvents(token: token)
        incomingRequests = (await requests ?? []).filter(\.incoming).count
        pendingPlanInvites = (await plans ?? []).filter { $0.myStatus == "invited" }.count
        let popularRows = await popular ?? []
        friendsPopularNames = Dictionary(popularRows.map { ($0.id, $0.names) }, uniquingKeysWith: { first, _ in first })
        if let eventRepository, !popularRows.isEmpty {
            let loaded = (try? await eventRepository.events(ids: popularRows.map(\.id))) ?? []
            let enriched = (try? await eventRepository.enrichingImages(in: loaded)) ?? loaded
            let order = Dictionary(uniqueKeysWithValues: popularRows.enumerated().map { ($1.id, $0) })
            friendsPopular = enriched.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        } else {
            friendsPopular = []
        }
    }
}
