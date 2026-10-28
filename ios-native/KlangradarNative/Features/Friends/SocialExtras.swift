// Erstellt von Claude Code (Nutzerwunsch 28.10.2026: Social ausbauen, Migration 000128):
// "Ich komme mit", Applaus und Kommentare im Nachklang, Konzert-Buddys,
// "Euer Jahr" und Gruppen.
import SwiftUI

// MARK: - Modelle

struct EchoComment: Identifiable, Sendable, Hashable {
    let id: UUID
    let person: SocialPerson
    let body: String
    let createdAt: Date?
    let isMine: Bool
}

struct FriendEcho: Identifiable, Sendable, Hashable {
    var id: String { "\(person.id)-\(event.id)" }
    let person: SocialPerson
    let event: SocialEvent
    let stars: Int
    let comment: String?
    var applause: Int
    var applauded: Bool
    var comments: [EchoComment]
    let isMine: Bool
}

struct BuddySuggestion: Identifiable, Sendable, Hashable {
    var id: String { "\(event.id)-\(friend.id)" }
    let event: SocialEvent
    let friend: SocialPerson
    let reason: String
}

struct SharedYear: Sendable, Hashable {
    let year: Int
    let concerts: Int
    let firstTitle: String?
    let firstDate: Date?
    let topVenue: String?
    let topComposer: String?
    let plans: Int
    let upcoming: Int
}

struct SocialGroup: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let emoji: String?
    let members: [SocialPerson]
    let upcoming: Int
    var title: String { [emoji, name].compactMap { $0 }.joined(separator: " ") }
    /// Mitglieder ohne mich, nur eigene Freunde (für Einladungen).
    let invitableIDs: [UUID]
}

struct GroupConcert: Identifiable, Sendable, Hashable {
    var id: UUID { event.id }
    let event: SocialEvent
    let people: [SocialPerson]
    let iAmGoing: Bool
}

// MARK: - RPCs

extension UserRepository {
    @discardableResult
    func joinFriendConcert(eventID: UUID, friendID: UUID, token: String) async throws -> UUID? {
        let value: JSONValue = try await client.rpc("join_friend_concert", parameters: [
            "p_event_id": .string(eventID.uuidString), "p_friend_id": .string(friendID.uuidString)
        ], accessToken: token)
        if case let .string(id) = value { return UUID(uuidString: id) }
        return nil
    }

    func friendEchoes(token: String) async throws -> [FriendEcho] {
        let value: JSONValue = try await client.rpc("friend_echoes", parameters: ["p_limit": .number(20)], accessToken: token)
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item -> FriendEcho? in
            guard case let .object(row) = item, let person = row.person(), let event = row.socialEvent(), let stars = row.integer("stars") else { return nil }
            let comments = row.objects("comments").compactMap { c -> EchoComment? in
                guard let id = c.uuid("id"), let author = c.person(), let body = c.string("body") else { return nil }
                return EchoComment(id: id, person: author, body: body, createdAt: c.date("created_at"), isMine: c.bool("mine") ?? false)
            }
            return FriendEcho(person: person, event: event, stars: stars, comment: row.string("comment"),
                              applause: row.integer("applause") ?? 0, applauded: row.bool("applauded") ?? false, comments: comments,
                              isMine: row.bool("mine") ?? false)
        }
    }

    func toggleApplause(ratingUser: UUID, eventID: UUID, token: String) async throws -> Bool {
        let value: JSONValue = try await client.rpc("toggle_rating_applause", parameters: [
            "p_rating_user": .string(ratingUser.uuidString), "p_event_id": .string(eventID.uuidString)
        ], accessToken: token)
        if case let .bool(on) = value { return on }
        return false
    }

    func commentOnRating(ratingUser: UUID, eventID: UUID, body: String, token: String) async throws {
        let _: JSONValue = try await client.rpc("comment_on_rating", parameters: [
            "p_rating_user": .string(ratingUser.uuidString), "p_event_id": .string(eventID.uuidString), "p_body": .string(body)
        ], accessToken: token)
    }

    func deleteRatingComment(_ id: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("delete_rating_comment", parameters: ["p_id": .string(id.uuidString)], accessToken: token)
    }

    func concertBuddies(token: String) async throws -> [BuddySuggestion] {
        let rows: [JSONObject] = try await client.rpc("concert_buddy_suggestions", parameters: ["p_limit": .number(10)], accessToken: token)
        return rows.compactMap { row in
            guard let event = row.socialEvent(), let friend = row.person(idKey: "friend_id") else { return nil }
            return BuddySuggestion(event: event, friend: friend, reason: row.string("reason") ?? "")
        }
    }

    func sharedYear(with friendID: UUID, year: Int, token: String) async throws -> SharedYear? {
        let row: JSONObject? = try? await client.rpc("shared_year_with", parameters: [
            "p_friend_id": .string(friendID.uuidString), "p_year": .number(Double(year))
        ], accessToken: token)
        guard let row else { return nil }
        let first = row.object("first")
        return SharedYear(year: year, concerts: row.integer("concerts") ?? 0, firstTitle: first?.string("title"), firstDate: first?.date("start"),
                          topVenue: row.string("top_venue"), topComposer: row.string("top_composer"),
                          plans: row.integer("plans") ?? 0, upcoming: row.integer("upcoming") ?? 0)
    }

    func socialGroups(token: String) async throws -> [SocialGroup] {
        let value: JSONValue = try await client.rpc("my_social_groups", accessToken: token)
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item -> SocialGroup? in
            guard case let .object(row) = item, let id = row.uuid("id"), let name = row.string("name") else { return nil }
            let memberRows = row.objects("members")
            return SocialGroup(id: id, name: name, emoji: row.string("emoji"),
                               members: memberRows.compactMap { $0.person() },
                               upcoming: row.integer("upcoming") ?? 0,
                               invitableIDs: memberRows.filter { ($0.bool("is_friend") ?? false) && !($0.bool("is_me") ?? false) }.compactMap { $0.uuid("user_id") })
        }
    }

    @discardableResult
    func createSocialGroup(name: String, emoji: String?, memberIDs: [UUID], token: String) async throws -> UUID? {
        let value: JSONValue = try await client.rpc("create_social_group", parameters: [
            "p_name": .string(name), "p_emoji": emoji.map(JSONValue.string) ?? .null,
            "p_member_ids": .array(memberIDs.map { .string($0.uuidString) })
        ], accessToken: token)
        if case let .string(id) = value { return UUID(uuidString: id) }
        return nil
    }

    func addSocialGroupMembers(_ groupID: UUID, memberIDs: [UUID], token: String) async throws {
        let _: JSONValue = try await client.rpc("add_social_group_members", parameters: [
            "p_group_id": .string(groupID.uuidString), "p_member_ids": .array(memberIDs.map { .string($0.uuidString) })
        ], accessToken: token)
    }

    func updateSocialGroup(_ groupID: UUID, name: String, emoji: String?, token: String) async throws {
        let _: JSONValue = try await client.rpc("update_social_group", parameters: [
            "p_group_id": .string(groupID.uuidString), "p_name": .string(name), "p_emoji": emoji.map(JSONValue.string) ?? .null
        ], accessToken: token)
    }

    func leaveSocialGroup(_ groupID: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("leave_social_group", parameters: ["p_group_id": .string(groupID.uuidString)], accessToken: token)
    }

    func groupConcerts(_ groupID: UUID, token: String) async throws -> [GroupConcert] {
        let rows: [JSONObject] = try await client.rpc("social_group_concerts", parameters: ["p_group_id": .string(groupID.uuidString)], accessToken: token)
        return rows.compactMap { row in
            guard let event = row.socialEvent() else { return nil }
            return GroupConcert(event: event, people: row.objects("people").compactMap { $0.person() }, iAmGoing: row.bool("i_am_going") ?? false)
        }
    }
}

// MARK: - Ich komme mit

/// Kleiner Knopf an Konzerten von Freunden: legt einen gemeinsamen Plan an
/// (oder tritt dem des Freundes bei) und sagt Bescheid.
struct JoinFriendButton: View {
    let event: SocialEvent
    let friend: SocialPerson
    @State private var state: Phase = .idle
    private enum Phase { case idle, busy, done, failed }

    var body: some View {
        Button {
            Task { await join() }
        } label: {
            Group {
                switch state {
                case .busy: ProgressView().controlSize(.small)
                case .done: Label("Dabei", systemImage: "checkmark")
                case .failed: Label("Nochmal", systemImage: "arrow.clockwise")
                case .idle: Label("Ich komme mit", systemImage: "figure.2")
                }
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(state == .done ? .white : KlangradarTheme.accent)
            .background(state == .done ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(0.12)), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(state == .busy || state == .done)
        .accessibilityHint("Plant das Konzert gemeinsam mit \(friend.name) und sagt Bescheid")
    }

    private func join() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        state = .busy
        do {
            try await repository.joinFriendConcert(eventID: event.id, friendID: friend.id, token: token)
            state = .done
            Haptics.confirm()
            await SocialStore.shared.refresh()
        } catch {
            state = .failed
        }
    }
}

// MARK: - Nachklang mit Applaus und Kommentaren

struct EchoSection: View {
    @State private var echoes: [FriendEcho] = []
    @State private var openEcho: FriendEcho?
    let reloadToken: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !echoes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nachklang").font(.system(.title2, design: .serif).weight(.semibold))
                    Text("Wie es deinen Freunden gefallen hat. Applaudiere oder antworte.").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach($echoes) { $echo in
                            EchoCard(echo: $echo) { openEcho = echo }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .task(id: reloadToken) { await load() }
        .sheet(item: $openEcho, onDismiss: { Task { await load() } }) { echo in
            NavigationStack { EchoThreadView(echo: echo) }
                .presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        echoes = (try? await repository.friendEchoes(token: token)) ?? []
    }
}

private struct EchoCard: View {
    @Binding var echo: FriendEcho
    let openThread: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SocialAvatar(name: echo.person.name, url: echo.person.avatarURL, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(echo.isMine ? "Du" : echo.person.name).font(.caption.weight(.semibold))
                    StarRating(stars: .constant(echo.stars), size: 10, editable: false)
                }
            }
            Text(echo.comment.map { "„\($0)“" } ?? "\(echo.stars) von 5 Sternen")
                .font(.system(.body, design: .serif)).italic()
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { DeepLinkRouter.shared.handle(route: "/event/\(echo.event.slug)") } label: {
                Text(echo.event.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button { Task { await applaud() } } label: {
                    Label("\(echo.applause)", systemImage: echo.applauded ? "hands.clap.fill" : "hands.clap")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(echo.applauded ? KlangradarTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(echo.isMine)
                .accessibilityLabel(echo.applauded ? "Applaus zurücknehmen" : "Applaudieren")
                Button(action: openThread) {
                    Label("\(echo.comments.count)", systemImage: "bubble.left")
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(echo.comments.count) Kommentare, antworten")
            }
        }
        .padding(16)
        .frame(width: 260, height: 230, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func applaud() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        let before = echo
        echo.applauded.toggle()
        echo.applause += echo.applauded ? 1 : -1
        Haptics.light()
        do {
            let on = try await repository.toggleApplause(ratingUser: echo.person.id, eventID: echo.event.id, token: token)
            if on != echo.applauded { echo = before }
        } catch {
            echo = before
        }
    }
}

private struct EchoThreadView: View {
    @State var echo: FriendEcho
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        SocialAvatar(name: echo.person.name, url: echo.person.avatarURL, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(echo.person.name).font(.headline)
                            Text(echo.event.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    StarRating(stars: .constant(echo.stars), size: 14, editable: false)
                    if let comment = echo.comment { Text(comment).font(.system(.body, design: .serif)).italic() }
                }
                .padding(.vertical, 4)
            }
            Section(echo.comments.isEmpty ? "Noch keine Antworten" : "Antworten") {
                ForEach(echo.comments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        SocialAvatar(name: comment.person.name, url: comment.person.avatarURL, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.isMine ? "Du" : comment.person.name).font(.caption.weight(.semibold))
                            Text(comment.body).font(.subheadline)
                        }
                    }
                    .swipeActions {
                        if comment.isMine || echo.isMine {
                            Button("Löschen", role: .destructive) { Task { await delete(comment) } }
                        }
                    }
                }
            }
            if let errorMessage { Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) } }
        }
        .navigationTitle("Nachklang")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                TextField("Antworten …", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Senden")
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func send() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        isSending = true
        defer { isSending = false }
        do {
            try await repository.commentOnRating(ratingUser: echo.person.id, eventID: echo.event.id, body: text, token: token)
            draft = ""
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = "Die Antwort konnte nicht gesendet werden."
        }
    }

    private func delete(_ comment: EchoComment) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.deleteRatingComment(comment.id, token: token)
        await reload()
    }

    private func reload() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        if let fresh = (try? await repository.friendEchoes(token: token))?.first(where: { $0.id == echo.id }) { echo = fresh }
    }
}

// MARK: - Konzert-Buddys

struct BuddySection: View {
    let reloadToken: Int
    @State private var suggestions: [BuddySuggestion] = []
    @State private var asked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nimm jemanden mit").font(.system(.title2, design: .serif).weight(.semibold))
                    Text("Freunde, die zu deinen gemerkten Konzerten passen").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(suggestions) { item in card(item) }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .task(id: reloadToken) {
            guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
            suggestions = (try? await repository.concertBuddies(token: token)) ?? []
        }
    }

    private func card(_ item: BuddySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: -10) {
                CachedAsyncImage(url: item.event.imageURL, maxPixel: 240) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { KlangradarTheme.accent.opacity(0.15).overlay { Image(systemName: "music.note").foregroundStyle(KlangradarTheme.accent) } }
                }
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                SocialAvatar(name: item.friend.name, url: item.friend.avatarURL, size: 40)
                    .overlay { Circle().stroke(Color(uiColor: .secondarySystemBackground), lineWidth: 3) }
                    .offset(y: 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.friend.name).font(.headline).lineLimit(1)
                Text(item.reason).font(.caption).foregroundStyle(KlangradarTheme.accent).lineLimit(1)
                Text(item.event.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(item.event.start.map { KlangradarDateTime.string($0, format: "EE d. MMM") } ?? "").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                Task { await ask(item) }
            } label: {
                Label(asked.contains(item.id) ? "Gefragt" : "Fragen", systemImage: asked.contains(item.id) ? "checkmark" : "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(KlangradarTheme.accent)
            .disabled(asked.contains(item.id))
        }
        .padding(14)
        .frame(width: 200, height: 250, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func ask(_ item: BuddySuggestion) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        if (try? await repository.createConcertPlan(eventID: item.event.id, friendIDs: [item.friend.id], meetingPoint: nil, meetingTime: nil, note: nil, token: token)) != nil {
            asked.insert(item.id)
            Haptics.confirm()
        }
    }
}

// MARK: - Euer Jahr

struct SharedYearCard: View {
    let friendID: UUID
    let friendName: String
    @State private var shared: SharedYear?

    private var year: Int { KlangradarDateTime.calendar.component(.year, from: .now) }

    var body: some View {
        Group {
            if let shared, shared.concerts > 0 || shared.upcoming > 0 {
                VStack(alignment: .leading, spacing: 14) {
                    Text("EUER JAHR \(String(shared.year))").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(shared.concerts)").font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(shared.concerts == 1 ? "Konzert zusammen" : "Konzerte zusammen").font(.headline)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if let venue = shared.topVenue { line("building.columns.fill", "Euer Saal", venue) }
                        if let composer = shared.topComposer { line("music.note", "Am meisten gehört", composer) }
                        if let first = shared.firstTitle { line("sparkles", "Angefangen mit", first) }
                        if shared.upcoming > 0 { line("calendar", "Noch vor euch", "\(shared.upcoming) \(shared.upcoming == 1 ? "Konzert" : "Konzerte")") }
                    }
                }
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [KlangradarTheme.accent, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 24, style: .continuous)
                )
                .padding(.horizontal, KlangradarTheme.pagePadding)
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: friendID) {
            guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
            shared = try? await repository.sharedYear(with: friendID, year: year, token: token)
        }
    }

    private func line(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).frame(width: 18).opacity(0.8)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).opacity(0.75)
                Text(value).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
        }
    }
}

// MARK: - Gruppen

struct GroupsSection: View {
    let reloadToken: Int
    @State private var groups: [SocialGroup] = []
    @State private var showsCreate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Gruppen").font(.system(.title2, design: .serif).weight(.semibold))
                Text(groups.isEmpty ? "Für den Chor, die Abo-Nachbarn oder die Oper-Clique" : "Wohin eure Runden gehen").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { showsCreate = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.title2.weight(.medium))
                            Text("Neue Gruppe").font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(KlangradarTheme.accent)
                        .frame(width: 150, height: 120)
                        .background {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(KlangradarTheme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(groups) { group in
                        NavigationLink { GroupDetailView(group: group) } label: { tile(group) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
        }
        .task(id: reloadToken) { await load() }
        .sheet(isPresented: $showsCreate, onDismiss: { Task { await load() } }) {
            NavigationStack { GroupEditorView(group: nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialGroupsChanged)) { _ in Task { await load() } }
    }

    private func tile(_ group: SocialGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.emoji ?? "🎻").font(.largeTitle)
            Text(group.name).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                AvatarStack(people: group.members, size: 20, limit: 4)
                if group.upcoming > 0 {
                    Text("\(group.upcoming) geplant").font(.caption2.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                }
            }
        }
        .padding(14)
        .frame(width: 170, height: 120, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        groups = (try? await repository.socialGroups(token: token)) ?? []
    }
}

extension Notification.Name {
    static let socialGroupsChanged = Notification.Name("klangradar.socialGroupsChanged")
}

struct GroupDetailView: View {
    @State var group: SocialGroup
    @State private var concerts: [GroupConcert] = []
    @State private var isLoading = true
    @State private var showsEdit = false
    @State private var showsAdd = false
    @State private var addSelection: Set<UUID> = []
    @State private var confirmsLeave = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text(group.emoji ?? "🎻").font(.system(size: 56))
                    Text(group.name).font(.system(.title, design: .serif).weight(.semibold))
                    Text("\(group.members.count) \(group.members.count == 1 ? "Mitglied" : "Mitglieder")").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("Da geht ihr hin") {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if concerts.isEmpty {
                    Text("Noch hat niemand aus der Gruppe ein Konzert zugesagt. Öffne ein Konzert und tippe auf „Mit Freunden planen“, dort kannst du die ganze Gruppe auf einmal einladen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(concerts) { concert in
                    SocialEventRow(event: concert.event, trailing: AnyView(
                        VStack(alignment: .trailing, spacing: 4) {
                            AvatarStack(people: concert.people, size: 22, limit: 3)
                            if concert.iAmGoing { Text("Du auch").font(.caption2.weight(.semibold)).foregroundStyle(KlangradarTheme.accent) }
                        }
                    ))
                }
            }

            Section("Mitglieder") {
                ForEach(group.members) { member in
                    HStack(spacing: 12) {
                        SocialAvatar(name: member.name, url: member.avatarURL, size: 36)
                        Text(member.id == SocialStore.shared.auth?.userID ? "Du" : member.name)
                    }
                }
                Button("Freunde hinzufügen", systemImage: "person.badge.plus") { showsAdd = true }
            }

            Section {
                Button("Gruppe bearbeiten", systemImage: "pencil") { showsEdit = true }
                Button("Gruppe verlassen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmsLeave = true }
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsEdit, onDismiss: { Task { await load() } }) {
            NavigationStack { GroupEditorView(group: group) }
        }
        .sheet(isPresented: $showsAdd, onDismiss: { addSelection = [] }) {
            NavigationStack {
                Form { FriendPicker(selection: $addSelection, excluded: Set(group.members.map(\.id)), showsGroups: false) }
                    .navigationTitle("Hinzufügen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showsAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Hinzufügen") { Task { await add() } }.disabled(addSelection.isEmpty)
                        }
                    }
            }
        }
        .confirmationDialog("Gruppe „\(group.name)“ verlassen?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Verlassen", role: .destructive) { Task { await leave() } }
        } message: {
            Text("Die anderen bleiben in der Gruppe. Bist du die letzte Person, wird sie gelöscht.")
        }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { isLoading = false; return }
        async let groupRows = try? repository.socialGroups(token: token)
        async let concertRows = try? repository.groupConcerts(group.id, token: token)
        if let fresh = (await groupRows)?.first(where: { $0.id == group.id }) { group = fresh }
        concerts = await concertRows ?? []
        isLoading = false
    }

    private func add() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.addSocialGroupMembers(group.id, memberIDs: Array(addSelection), token: token)
        showsAdd = false
        NotificationCenter.default.post(name: .socialGroupsChanged, object: nil)
        await load()
    }

    private func leave() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.leaveSocialGroup(group.id, token: token)
        NotificationCenter.default.post(name: .socialGroupsChanged, object: nil)
        dismiss()
    }
}

struct GroupEditorView: View {
    let group: SocialGroup?
    @State private var name = ""
    @State private var emoji = "🎻"
    @State private var selection: Set<UUID> = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let emojis = ["🎻", "🎹", "🎺", "🎼", "🎭", "🎤", "🥂", "🎶", "🏛️", "❤️"]

    var body: some View {
        Form {
            Section("Name") {
                TextField("z. B. Chor, Abo-Nachbarn", text: $name)
                    .textInputAutocapitalization(.sentences)
            }
            Section("Symbol") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(emojis, id: \.self) { item in
                            Button { emoji = item } label: {
                                Text(item).font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(emoji == item ? KlangradarTheme.accent.opacity(0.18) : Color.clear, in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Symbol \(item)")
                        }
                    }
                }
            }
            if group == nil {
                Section {
                    FriendPicker(selection: $selection, showsGroups: false)
                } header: {
                    Text("Wer ist dabei?")
                } footer: {
                    Text("Du kannst nur eigene Freunde hinzufügen. Alle sehen, zu welchen Konzerten die anderen zugesagt haben.")
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) } }
        }
        .navigationTitle(group == nil ? "Neue Gruppe" : "Gruppe bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(group == nil ? "Erstellen" : "Sichern") { Task { await save() } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let group { name = group.name; emoji = group.emoji ?? "🎻" }
        }
    }

    private func save() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        do {
            if let group {
                try await repository.updateSocialGroup(group.id, name: trimmed, emoji: emoji, token: token)
            } else {
                try await repository.createSocialGroup(name: trimmed, emoji: emoji, memberIDs: Array(selection), token: token)
            }
            Haptics.confirm()
            NotificationCenter.default.post(name: .socialGroupsChanged, object: nil)
            dismiss()
        } catch {
            errorMessage = "Das hat nicht geklappt. Bitte versuch es noch einmal."
        }
    }
}
