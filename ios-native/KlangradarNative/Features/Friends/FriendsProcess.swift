import Foundation

// Freunde-Ausbau 28.10.2026 (Migration 000129, erstellt von Claude Code):
// "Wer war noch da?", Einladungs-Begrüßung, Verbunden-Ansicht, enge Freunde,
// Stummschalten, "Ticket übrig" und "Privat hingehen".

struct ConcertCompanion: Identifiable, Sendable, Hashable {
    var id: UUID { person.id }
    let person: SocialPerson
    let event: SocialEvent
}

/// Nach dem Verbinden: was ihr gemeinsam vorhabt und wohin der Freund geht.
struct FriendConnection: Identifiable, Sendable, Hashable {
    var id: UUID { person.id }
    let person: SocialPerson
    let tasteMatch: Int?
    let shared: [SocialEvent]
    let upcoming: [SocialEvent]
}

enum InviteAcceptance: Sendable {
    case connected(FriendConnection?, name: String?, isNew: Bool)
    case unknownCode
    case ownCode
}

struct TicketOffer: Identifiable, Sendable, Hashable {
    let id: UUID
    let event: SocialEvent
    let person: SocialPerson
    let note: String?
    let status: String
    let mine: Bool
    let takenByMe: Bool
    let takenByName: String?

    var isOpen: Bool { status == "open" }
}

struct EventSocialState: Sendable {
    var isPrivate = false
    var myStatus: String?
    var offers: [TicketOffer] = []

    var myOffer: TicketOffer? { offers.first { $0.mine } }
    var friendOffers: [TicketOffer] { offers.filter { !$0.mine } }
}

struct ProfileRating: Identifiable, Sendable, Hashable {
    var id: UUID { event.id }
    let event: SocialEvent
    let stars: Int
    let comment: String?
}

extension FriendRequest {
    /// Woher die Anfrage kommt, als kurzer Satz.
    var contextLine: String? {
        switch source {
        case "concert": context.map { "Wart beide bei \($0)" } ?? "Wart beim selben Konzert"
        case "contacts": "Aus deinen Kontakten"
        case "search": incoming ? "Hat dich über die Suche gefunden" : "Über die Suche"
        case "suggestion": "Über Vorschläge"
        case "buddy": "Über Konzert-Buddys"
        case "code", "invite": "Über den Freundescode"
        default: nil
        }
    }

    var composersLine: String? {
        guard !sharedComposers.isEmpty else { return nil }
        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        return "Ihr hört beide gern \(formatter.string(from: sharedComposers) ?? sharedComposers.joined(separator: ", "))"
    }
}

/// Freundescode aus QR-Code, Link oder Texteingabe.
enum FriendCodeParser {
    static func code(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.scheme != nil {
            let parts = url.path.split(separator: "/")
            if url.host?.hasSuffix("klangradar.com") == true, parts.count == 2, parts[0] == "f" { return valid(String(parts[1])) }
            if url.scheme == "de.klangradar.native", url.host == "friend" { return valid(url.lastPathComponent) }
            return nil
        }
        return valid(text)
    }

    private static func valid(_ value: String) -> String? {
        let upper = value.uppercased()
        guard (6...12).contains(upper.count), upper.allSatisfy({ $0.isLetter || $0.isNumber }), upper.allSatisfy(\.isASCII) else { return nil }
        return upper
    }
}

extension JSONObject {
    func socialEvents(_ key: String) -> [SocialEvent] { objects(key).compactMap { $0.socialEvent() } }

    func friendConnection() -> FriendConnection? {
        guard let person = person() else { return nil }
        return FriendConnection(person: person, tasteMatch: integer("taste_match"), shared: socialEvents("shared"), upcoming: socialEvents("upcoming"))
    }

    func ticketOffer() -> TicketOffer? {
        guard let id = uuid("offer_id"), let event = socialEvent(), let person = person() else { return nil }
        return TicketOffer(id: id, event: event, person: person, note: string("note"), status: string("status") ?? "open",
                           mine: bool("mine") ?? false, takenByMe: bool("taken_by_me") ?? false, takenByName: string("taken_by_name"))
    }
}

extension UserRepository {
    func concertCompanions(token: String) async throws -> [ConcertCompanion] {
        let rows: [JSONObject] = try await client.rpc("concert_companions", accessToken: token)
        return rows.compactMap { row in
            guard let person = row.person(detail: row.string("reason")), let event = row.socialEvent() else { return nil }
            return ConcertCompanion(person: person, event: event)
        }
    }

    func friendConnection(_ friendID: UUID, token: String) async throws -> FriendConnection? {
        let row: JSONObject? = try? await client.rpc("friend_connection", parameters: ["p_friend_id": .string(friendID.uuidString)], accessToken: token)
        return row?.friendConnection()
    }

    /// Code, QR-Code oder Einladungslink: verbindet sofort und liefert die Begrüßung.
    func acceptFriendInvite(code: String, token: String) async throws -> InviteAcceptance {
        let row: JSONObject = try await client.rpc("accept_friend_invite", parameters: ["p_code": .string(code)], accessToken: token)
        guard row.bool("ok") == true else { return row.string("reason") == "own_code" ? .ownCode : .unknownCode }
        return .connected(row.object("connection")?.friendConnection(), name: row.string("display_name"), isNew: row.bool("is_new") ?? true)
    }

    func setCloseFriend(_ friendID: UUID, close: Bool, token: String) async throws {
        let _: JSONValue = try await client.rpc("set_close_friend", parameters: ["p_friend_id": .string(friendID.uuidString), "p_close": .bool(close)], accessToken: token)
    }

    func setFriendMuted(_ friendID: UUID, muted: Bool, token: String) async throws {
        let _: JSONValue = try await client.rpc("set_friend_muted", parameters: ["p_friend_id": .string(friendID.uuidString), "p_muted": .bool(muted)], accessToken: token)
    }

    func setConcertPrivate(eventID: UUID, isPrivate: Bool, token: String) async throws {
        let _: JSONValue = try await client.rpc("set_concert_private", parameters: ["p_event_id": .string(eventID.uuidString), "p_private": .bool(isPrivate)], accessToken: token)
    }

    func eventSocialState(eventID: UUID, token: String) async throws -> EventSocialState {
        let row: JSONObject = try await client.rpc("event_social_state", parameters: ["p_event_id": .string(eventID.uuidString)], accessToken: token)
        return EventSocialState(isPrivate: row.bool("is_private") ?? false, myStatus: row.string("my_status"), offers: row.objects("offers").compactMap { $0.ticketOffer() })
    }

    func ticketOffers(token: String) async throws -> [TicketOffer] {
        let value: JSONValue = try await client.rpc("ticket_offers_for_me", accessToken: token)
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item in
            guard case let .object(row) = item else { return nil }
            return row.ticketOffer()
        }
    }

    func offerTicket(eventID: UUID, note: String?, token: String) async throws {
        let _: JSONValue = try await client.rpc("offer_ticket", parameters: ["p_event_id": .string(eventID.uuidString), "p_note": note.map(JSONValue.string) ?? .null], accessToken: token)
    }

    func withdrawTicketOffer(_ id: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("withdraw_ticket_offer", parameters: ["p_offer_id": .string(id.uuidString)], accessToken: token)
    }

    /// "ok", "taken" (jemand war schneller) oder "not_allowed".
    func claimTicketOffer(_ id: UUID, token: String) async throws -> String {
        let value: JSONValue = try await client.rpc("claim_ticket_offer", parameters: ["p_offer_id": .string(id.uuidString)], accessToken: token)
        if case let .string(result) = value { return result }
        return "not_allowed"
    }
}
