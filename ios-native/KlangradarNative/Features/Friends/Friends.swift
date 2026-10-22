import SwiftUI

/// "Mit Freunden" (Migration 000027): Freundschaft per Code, Freunde sehen
/// gegenseitig nur, zu welchen kommenden Konzerten man "hingeht".
struct Friend: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    let upcomingCount: Int
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
            return Friend(id: id, name: row.string("display_name") ?? "Klangradar-Freund:in", avatarURL: row.string("avatar_url").flatMap(URL.init(string:)), upcomingCount: row.integer("upcoming_count") ?? 0)
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

/// Einladungslink: öffnet die App direkt mit dem Code (DeepLinkRouter).
enum FriendInvite {
    static func link(code: String) -> URL { URL(string: "de.klangradar.native://friend/\(code)")! }

    static func message(code: String) -> String {
        "Lass uns auf Klangradar sehen, zu welchen Konzerten wir gehen. Mein Freundescode: \(code)\n\(link(code: code).absoluteString)"
    }
}

struct FriendsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @ObservedObject private var deepLinks = DeepLinkRouter.shared
    @State private var code: String?
    @State private var friends: [Friend] = []
    @State private var events: [FriendEvent] = []
    @State private var codeInput = ""
    @State private var message: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if auth.userID == nil {
                ContentUnavailableView("Melde dich an", systemImage: "person.2", description: Text("Mit einem Konto kannst du Freunde hinzufügen und sehen, wohin sie gehen."))
            } else {
                Section {
                    if let code {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dein Freundescode").font(.caption).foregroundStyle(.secondary)
                                Text(code).font(.title2.monospaced().bold())
                            }
                            Spacer()
                            ShareLink(item: FriendInvite.message(code: code)) {
                                Label("Einladen", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(KlangradarTheme.accent)
                        }
                    } else if isLoading {
                        ProgressView()
                    }
                    HStack {
                        TextField("Code eines Freundes", text: $codeInput)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                        Button("Hinzufügen") { Task { await add(codeInput) } }
                            .disabled(codeInput.trimmingCharacters(in: .whitespaces).count < 6)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text("Freunde sehen nur Konzerte, bei denen du „Ich gehe hin“ gewählt hast – nicht deine Merkliste.")
                }

                if !events.isEmpty {
                    Section("Was deine Freunde vorhaben") {
                        ForEach(events) { event in
                            Button {
                                DeepLinkRouter.shared.handle(route: "/event/\(event.slug)")
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                    Text([event.start.map { KlangradarDateTime.string($0, format: "EEE, d. MMM HH:mm") }, event.venue].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Label(event.friendNames.joined(separator: ", "), systemImage: "person.2.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                                }
                            }
                        }
                    }
                }

                Section("Freunde") {
                    if friends.isEmpty && !isLoading {
                        Text("Noch keine Freunde. Teile deinen Code, um loszulegen.").foregroundStyle(.secondary)
                    }
                    ForEach(friends) { friend in
                        HStack(spacing: 12) {
                            AsyncImage(url: friend.avatarURL) { $0.resizable().scaledToFill() } placeholder: {
                                Circle().fill(.quaternary).overlay { Text(String(friend.name.prefix(1))).font(.headline) }
                            }
                            .frame(width: 38, height: 38)
                            .clipShape(.circle)
                            VStack(alignment: .leading) {
                                Text(friend.name)
                                Text(friend.upcomingCount == 1 ? "1 kommendes Konzert" : "\(friend.upcomingCount) kommende Konzerte").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Entfernen", role: .destructive) { Task { await remove(friend) } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Freunde")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: deepLinks.pendingFriendCode) { _, value in
            guard let value else { return }
            deepLinks.pendingFriendCode = nil
            Task { await add(value) }
        }
    }

    private func load() async {
        guard let repository, let token = auth.accessToken else { isLoading = false; return }
        async let codeValue = try? repository.myFriendCode(token: token)
        async let friendRows = try? repository.friends(token: token)
        async let eventRows = try? repository.friendsUpcomingEvents(token: token)
        code = await codeValue
        friends = await friendRows ?? []
        events = await eventRows ?? []
        isLoading = false
        if let pending = deepLinks.pendingFriendCode {
            deepLinks.pendingFriendCode = nil
            await add(pending)
        }
    }

    private func add(_ raw: String) async {
        guard let repository, let token = auth.accessToken else { return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            switch try await repository.addFriend(code: value, token: token) {
            case .added(let name):
                Haptics.confirm()
                message = "\(name ?? "Neue:r Freund:in") ist jetzt in deiner Liste."
                codeInput = ""
                await load()
            case .unknownCode: message = "Diesen Code kennen wir nicht."
            case .ownCode: message = "Das ist dein eigener Code."
            }
        } catch {
            message = "Hinzufügen hat nicht geklappt. Bitte später erneut versuchen."
        }
    }

    private func remove(_ friend: Friend) async {
        guard let repository, let token = auth.accessToken else { return }
        try? await repository.removeFriend(friend.id, token: token)
        friends.removeAll { $0.id == friend.id }
        events = (try? await repository.friendsUpcomingEvents(token: token)) ?? events
    }
}

/// Konzertseite: Freunde, die hingehen, plus "Mit Freunden teilen".
struct FriendsAttendingRow: View {
    let event: ConcertEvent
    let shareURL: URL?
    @EnvironmentObject private var follows: FollowStore
    @State private var friends: [Friend] = []

    var body: some View {
        HStack(spacing: 10) {
            if !friends.isEmpty {
                HStack(spacing: -8) {
                    ForEach(friends.prefix(4)) { friend in
                        AsyncImage(url: friend.avatarURL) { $0.resizable().scaledToFill() } placeholder: {
                            Circle().fill(KlangradarTheme.accent.opacity(0.2)).overlay { Text(String(friend.name.prefix(1))).font(.caption.bold()) }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(.circle)
                        .overlay { Circle().stroke(.background, lineWidth: 2) }
                    }
                }
                Text(friends.count == 1 ? "\(friends[0].name) geht hin" : "\(friends[0].name) und \(friends.count - 1) weitere gehen hin")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            ShareLink(item: shareText) {
                Label("Mit Freunden teilen", systemImage: "person.2.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .task { friends = await follows.friendsAttending(eventID: event.id) }
    }

    private var shareText: String {
        var lines = ["Kommst du mit? \(event.title)", event.dateLine]
        if let shareURL { lines.append(shareURL.absoluteString) }
        lines.append("Gefunden mit Klangradar")
        return lines.joined(separator: "\n")
    }
}
