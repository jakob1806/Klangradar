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
    /// 09.11.2026: Antwort auf eine Nachricht, Foto.
    var replyTo: UUID? = nil
    var replyBody: String? = nil
    var replySender: String? = nil
    var imagePath: String? = nil
}

struct ChatMember: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    var lastReadAt: Date? = nil
    var typing = false
}

enum ChatReactions {
    static let all = ["👏", "❤️", "😂", "😮", "👍", "🎻"]
}

extension UserRepository {
    func chatInbox(token: String) async throws -> [ChatConversation] {
        let rows: [JSONObject] = try await client.rpc("chat_inbox", accessToken: token)
        ChatCache.store(rows, key: "inbox")
        return Self.parseInbox(rows)
    }

    /// Zuletzt geladener Posteingang (sofort beim Öffnen, 09.11.2026).
    func cachedChatInbox() -> [ChatConversation] { Self.parseInbox(ChatCache.load(key: "inbox")) }

    static func parseInbox(_ rows: [JSONObject]) -> [ChatConversation] {
        rows.compactMap { row in
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
        if let before { parameters["p_before"] = .string(FormatterCache.isoString(before)) }
        let rows: [JSONObject] = try await client.rpc("chat_thread", parameters: parameters, accessToken: token)
        if before == nil { ChatCache.store(rows, key: conversationID.uuidString) }
        return Self.parseThread(rows)
    }

    func cachedChatThread(_ conversationID: UUID) -> [ChatMessage] { Self.parseThread(ChatCache.load(key: conversationID.uuidString)) }

    static func parseThread(_ rows: [JSONObject]) -> [ChatMessage] {
        rows.compactMap { row -> ChatMessage? in
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
                               createdAt: created, deleted: row.bool("deleted") ?? false, event: event, reactions: reactions,
                               replyTo: row.uuid("reply_to"), replyBody: row.string("reply_body"), replySender: row.string("reply_sender"),
                               imagePath: row.string("image_path"))
        }
        .reversed()
    }

    func chatMembers(_ conversationID: UUID, token: String) async throws -> [ChatMember] {
        let rows: [JSONObject] = try await client.rpc("chat_members_of", parameters: ["p_conversation": .string(conversationID.uuidString)], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.uuid("user_id") else { return nil }
            return ChatMember(id: id, name: row.string("display_name") ?? "Klangradar-Freund:in", avatarURL: row.url("avatar_url"), lastReadAt: row.date("last_read_at"), typing: row.bool("typing") ?? false)
        }
    }

    @discardableResult
    func chatSend(_ conversationID: UUID, kind: String = "text", body: String?, eventID: UUID? = nil,
                  replyTo: UUID? = nil, imagePath: String? = nil, token: String) async throws -> UUID? {
        var parameters: JSONObject = ["p_conversation": .string(conversationID.uuidString), "p_kind": .string(kind),
                                      "p_body": body.map(JSONValue.string) ?? .null]
        parameters["p_event_id"] = eventID.map { .string($0.uuidString) } ?? .null
        if let replyTo { parameters["p_reply_to"] = .string(replyTo.uuidString) }
        if let imagePath { parameters["p_image_path"] = .string(imagePath) }
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

    /// „schreibt …“ – höchstens alle 4 Sekunden aufrufen.
    func chatTyping(_ conversationID: UUID, token: String) async {
        let _: JSONValue? = try? await client.rpc("chat_typing", parameters: ["p_conversation": .string(conversationID.uuidString)], accessToken: token)
    }

    /// Foto verkleinert hochladen (privater Bucket, Ordner = Gespräch).
    func chatUploadImage(_ data: Data, conversationID: UUID, token: String) async throws -> String {
        let path = "\(conversationID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.uploadPublicObject(bucket: "chat-images", path: path, data: data, contentType: "image/jpeg", accessToken: token)
        return path
    }

    func chatImageURL(_ path: String, token: String) async -> URL? {
        if let cached = await ChatImageURLCache.shared.url(for: path) { return cached }
        guard let url = try? await client.signedStorageURL(bucket: "chat-images", path: path, expiresIn: 3600, accessToken: token) else { return nil }
        await ChatImageURLCache.shared.set(url, for: path)
        return url
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

/// Signierte Foto-Links 50 Minuten wiederverwenden.
actor ChatImageURLCache {
    static let shared = ChatImageURLCache()
    private var entries: [String: (URL, Date)] = [:]
    func url(for path: String) -> URL? {
        guard let entry = entries[path], entry.1 > .now else { return nil }
        return entry.0
    }
    func set(_ url: URL, for path: String) { entries[path] = (url, .now.addingTimeInterval(3000)) }
}

/// Lokaler Zwischenspeicher für Posteingang und Verläufe (09.11.2026): Chats
/// erscheinen sofort, auch offline; die Server-Antwort ersetzt sie danach.
enum ChatCache {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("chat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func store(_ rows: [JSONObject], key: String) {
        guard let url = directory?.appendingPathComponent("\(key).json"),
              let data = try? JSONEncoder().encode(Array(rows.prefix(120))) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func load(key: String) -> [JSONObject] {
        guard let url = directory?.appendingPathComponent("\(key).json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([JSONObject].self, from: data)) ?? []
    }

    /// Beim Abmelden leeren.
    static func clear() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}

/// Merkt sich den gerade geöffneten Chat (kein Banner für ihn).
enum ChatPresence {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: UUID?
    static var openConversation: UUID? {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
    static func isOpen(route: String) -> Bool {
        openConversation.map { route.lowercased().contains($0.uuidString.lowercased()) } ?? false
    }
}

/// Weckt offene Chats, wenn eine Chat-Mitteilung eintrifft (statt
/// Sekundentakt-Abfragen). Gewartet wird lokal, ohne Netzwerk.
@MainActor
final class ChatSignal {
    static let shared = ChatSignal()
    private(set) var generation = 0
    func fire() { generation += 1 }

    /// Wartet bis zu `seconds`, kehrt früher zurück, sobald `fire()` kommt.
    func wait(seconds: Double) async {
        let start = generation
        var waited = 0.0
        while waited < seconds, generation == start, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            waited += 0.4
        }
    }
}
