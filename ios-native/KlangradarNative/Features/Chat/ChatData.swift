// Erstellt von Claude Code (08.11.2026): Chat zwischen Freunden –
// Einzel- und Gruppenchats, geteilte Konzerte, Einladungen, Reaktionen.
// Backend: Migration 20261231000163_friend_chat.sql (RPCs chat_*).
import Foundation

struct ChatConversation: Identifiable, Hashable, Sendable {
    let id: UUID
    let isGroup: Bool
    let title: String
    let icon: String?
    let otherUserID: UUID?
    let avatarURL: URL?
    let lastBody: String?
    let lastKind: String?
    let lastSenderName: String?
    let lastAt: Date?
    var unread: Int
    var muted: Bool
    let memberCount: Int

    var preview: String {
        switch lastKind {
        case "event": return "Hat ein Konzert geteilt"
        case "invite": return "Konzert-Einladung"
        case "system": return [lastSenderName, lastBody].compactMap { $0 }.joined(separator: " ")
        default:
            let text = lastBody ?? "Noch keine Nachrichten"
            if isGroup, let sender = lastSenderName { return "\(sender.split(separator: " ").first.map(String.init) ?? sender): \(text)" }
            return text
        }
    }
}

struct ChatReaction: Hashable, Sendable {
    let userID: UUID
    let emoji: String
}

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let senderID: UUID?
    let senderName: String
    let senderAvatar: URL?
    let kind: String
    let body: String?
    let createdAt: Date
    let deleted: Bool
    let event: SocialEvent?
    let reactions: [ChatReaction]
}

struct ChatMember: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    var lastReadAt: Date? = nil
}

enum ChatReactions {
    static let all = ["👏", "❤️", "😂", "😮", "👍", "🎻"]
}

extension UserRepository {
    func chatInbox(token: String) async throws -> [ChatConversation] {
        let rows: [JSONObject] = try await client.rpc("chat_inbox", accessToken: token)
        return rows.compactMap { row in
            guard let id = row.uuid("conversation_id") else { return nil }
            return ChatConversation(
                id: id, isGroup: row.bool("is_group") ?? false,
                title: row.string("title") ?? "Chat", icon: row.string("icon"),
                otherUserID: row.uuid("other_user_id"), avatarURL: row.url("avatar_url"),
                lastBody: row.string("last_body"), lastKind: row.string("last_kind"),
                lastSenderName: row.string("last_sender_name"), lastAt: row.date("last_at"),
                unread: row.integer("unread") ?? 0, muted: row.bool("muted") ?? false,
                memberCount: row.integer("member_count") ?? 2
            )
        }
    }

    func chatThread(_ conversationID: UUID, before: Date? = nil, token: String) async throws -> [ChatMessage] {
        var parameters: JSONObject = ["p_conversation": .string(conversationID.uuidString), "p_limit": .number(80)]
        if let before { parameters["p_before"] = .string(ISO8601DateFormatter().string(from: before)) }
        let rows: [JSONObject] = try await client.rpc("chat_thread", parameters: parameters, accessToken: token)
        return rows.compactMap { row -> ChatMessage? in
            guard let id = row.uuid("id"), let created = row.date("created_at") else { return nil }
            var event: SocialEvent?
            if let eventID = row.uuid("event_id"), let slug = row.string("slug"), let title = row.string("title") {
                event = SocialEvent(id: eventID, slug: slug, title: title, start: row.date("start_datetime"), venue: row.string("venue_name"), imageURL: row.url("image_url"))
            }
            let reactions = row.objects("reactions").compactMap { r -> ChatReaction? in
                guard let user = r.uuid("user_id"), let emoji = r.string("emoji") else { return nil }
                return ChatReaction(userID: user, emoji: emoji)
            }
            return ChatMessage(id: id, senderID: row.uuid("sender_id"), senderName: row.string("sender_name") ?? "Klangradar",
                               senderAvatar: row.url("sender_avatar"), kind: row.string("kind") ?? "text", body: row.string("body"),
                               createdAt: created, deleted: row.bool("deleted") ?? false, event: event, reactions: reactions)
        }
        .reversed()
    }

    func chatMembers(_ conversationID: UUID, token: String) async throws -> [ChatMember] {
        let rows: [JSONObject] = try await client.rpc("chat_members_of", parameters: ["p_conversation": .string(conversationID.uuidString)], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.uuid("user_id") else { return nil }
            return ChatMember(id: id, name: row.string("display_name") ?? "Klangradar-Freund:in", avatarURL: row.url("avatar_url"), lastReadAt: row.date("last_read_at"))
        }
    }

    @discardableResult
    func chatSend(_ conversationID: UUID, kind: String = "text", body: String?, eventID: UUID? = nil, token: String) async throws -> UUID? {
        var parameters: JSONObject = ["p_conversation": .string(conversationID.uuidString), "p_kind": .string(kind),
                                      "p_body": body.map(JSONValue.string) ?? .null]
        parameters["p_event_id"] = eventID.map { .string($0.uuidString) } ?? .null
        let value: JSONValue = try await client.rpc("chat_send", parameters: parameters, accessToken: token)
        return Self.uuid(from: value)
    }

    func chatOpenDirect(with friendID: UUID, token: String) async throws -> UUID? {
        let value: JSONValue = try await client.rpc("chat_open_direct", parameters: ["p_friend": .string(friendID.uuidString)], accessToken: token)
        return Self.uuid(from: value)
    }

    func chatCreateGroup(title: String, members: [UUID], icon: String?, token: String) async throws -> UUID? {
        let value: JSONValue = try await client.rpc("chat_create_group", parameters: [
            "p_title": .string(title), "p_members": .array(members.map { .string($0.uuidString) }), "p_icon": icon.map(JSONValue.string) ?? .null
        ], accessToken: token)
        return Self.uuid(from: value)
    }

    func chatAddMembers(_ conversationID: UUID, members: [UUID], token: String) async throws {
        let _: JSONValue = try await client.rpc("chat_add_members", parameters: [
            "p_conversation": .string(conversationID.uuidString), "p_members": .array(members.map { .string($0.uuidString) })
        ], accessToken: token)
    }

    func chatMarkRead(_ conversationID: UUID, token: String) async {
        let _: JSONValue? = try? await client.rpc("chat_mark_read", parameters: ["p_conversation": .string(conversationID.uuidString)], accessToken: token)
    }

    func chatReact(_ messageID: UUID, emoji: String?, token: String) async throws {
        let _: JSONValue = try await client.rpc("chat_react", parameters: [
            "p_message": .string(messageID.uuidString), "p_emoji": emoji.map(JSONValue.string) ?? .null
        ], accessToken: token)
    }

    func chatDelete(_ messageID: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("chat_delete_message", parameters: ["p_message": .string(messageID.uuidString)], accessToken: token)
    }

    func chatLeave(_ conversationID: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("chat_leave", parameters: ["p_conversation": .string(conversationID.uuidString)], accessToken: token)
    }

    func chatSetMuted(_ conversationID: UUID, muted: Bool, token: String) async throws {
        let _: JSONValue = try await client.rpc("chat_set_muted", parameters: ["p_conversation": .string(conversationID.uuidString), "p_muted": .bool(muted)], accessToken: token)
    }

    func chatUnreadTotal(token: String) async -> Int {
        let value: JSONValue? = try? await client.rpc("chat_unread_total", accessToken: token)
        if case let .number(n)? = value { return Int(n) }
        return 0
    }

    private static func uuid(from value: JSONValue) -> UUID? {
        if case let .string(raw) = value { return UUID(uuidString: raw) }
        return nil
    }
}
