// Erstellt von Claude Code (08.11.2026): Chat zwischen Freunden,
// aufgebaut wie ein vertrauter Messenger – Übersicht, Verlauf mit Blasen,
// geteilte Konzerte als Karten, Reaktionen per langem Druck, Gruppen.
import SwiftUI

// MARK: - Übersicht

struct ChatInboxView: View {
    @State private var conversations: [ChatConversation] = []
    @State private var isLoading = true
    @State private var showsNewChat = false
    @State private var path: [ChatRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && conversations.isEmpty {
                    ProgressView()
                } else if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Chats", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Schreib Freunden, teile Konzerte oder lade zu einem Abend ein.")
                    } actions: {
                        Button("Neuer Chat") { showsNewChat = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List(conversations) { conversation in
                        NavigationLink(value: ChatRoute(conversation: conversation)) { ChatInboxRow(conversation: conversation) }
                            .swipeActions(edge: .trailing) {
                                Button(conversation.muted ? "Ton an" : "Stumm", systemImage: conversation.muted ? "bell" : "bell.slash") {
                                    Task { await setMuted(conversation, !conversation.muted) }
                                }
                                .tint(.orange)
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Nachrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsNewChat = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Neuer Chat")
                }
            }
            .navigationDestination(for: ChatRoute.self) { route in
                ChatThreadView(conversationID: route.id, title: route.title, isGroup: route.isGroup)
            }
            .sheet(isPresented: $showsNewChat) {
                NewChatSheet { route in
                    showsNewChat = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(route)
                        await load()
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: .seconds(8))
                }
            }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { isLoading = false; return }
        if let loaded = try? await repository.chatInbox(token: token) { conversations = loaded }
        isLoading = false
    }

    private func setMuted(_ conversation: ChatConversation, _ muted: Bool) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.chatSetMuted(conversation.id, muted: muted, token: token)
        await load()
    }
}

struct ChatRoute: Hashable, Identifiable {
    let id: UUID
    let title: String
    let isGroup: Bool

    init(id: UUID, title: String, isGroup: Bool) { self.id = id; self.title = title; self.isGroup = isGroup }
    init(conversation: ChatConversation) { self.init(id: conversation.id, title: conversation.title, isGroup: conversation.isGroup) }
}

private struct ChatInboxRow: View {
    let conversation: ChatConversation

    var body: some View {
        HStack(spacing: 12) {
            ChatAvatar(title: conversation.title, url: conversation.avatarURL, isGroup: conversation.isGroup, icon: conversation.icon, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title).font(.headline).lineLimit(1)
                    if conversation.muted { Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(.secondary) }
                    Spacer(minLength: 6)
                    if let date = conversation.lastAt {
                        Text(ChatFormat.shortTime(date)).font(.caption)
                            .foregroundStyle(conversation.unread > 0 ? KlangradarTheme.accent : .secondary)
                    }
                }
                HStack {
                    Text(conversation.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 6)
                    if conversation.unread > 0 {
                        Text("\(conversation.unread)").font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(conversation.muted ? Color.gray : KlangradarTheme.accent, in: .capsule)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ChatAvatar: View {
    let title: String
    let url: URL?
    let isGroup: Bool
    var icon: String? = nil
    var size: CGFloat = 44

    var body: some View {
        if isGroup {
            Image(systemName: icon.flatMap { $0.hasPrefix("sf:") ? String($0.dropFirst(3)) : nil } ?? "person.3.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(KlangradarTheme.accent.gradient, in: .circle)
        } else {
            SocialAvatar(name: title, url: url, size: size)
        }
    }
}

enum ChatFormat {
    static func shortTime(_ date: Date) -> String {
        let calendar = KlangradarDateTime.calendar
        if calendar.isDateInToday(date) { return KlangradarDateTime.string(date, format: "HH:mm") }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        if date > .now.addingTimeInterval(-6 * 86_400) { return KlangradarDateTime.string(date, format: "EEEE") }
        return KlangradarDateTime.string(date, format: "dd.MM.yy")
    }

    static func dayHeader(_ date: Date) -> String {
        let calendar = KlangradarDateTime.calendar
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        return KlangradarDateTime.string(date, format: "EEEE, d. MMMM")
    }
}

// MARK: - Verlauf (Redesign 08.11.2026)

struct ChatThreadView: View {
    let conversationID: UUID
    let title: String
    let isGroup: Bool

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var members: [ChatMember] = []
    @State private var showsMembers = false
    @State private var error: String?
    @State private var focused: ChatMessage?
    @State private var didLoad = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var myID: UUID? { SocialStore.shared.auth?.userID }
    private var others: [ChatMember] { members.filter { $0.id != myID } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if didLoad && messages.isEmpty { emptyState }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        if previous == nil || !KlangradarDateTime.calendar.isDate(message.createdAt, inSameDayAs: previous!.createdAt) {
                            Text(ChatFormat.dayHeader(message.createdAt))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.top, 18).padding(.bottom, 10)
                        }
                        let startsGroup = !Self.sameGroup(previous, message)
                        let endsGroup = !Self.sameGroup(message, next)
                        ChatBubble(
                            message: message,
                            isMine: message.senderID == myID,
                            isGroupChat: isGroup,
                            startsGroup: startsGroup,
                            endsGroup: endsGroup,
                            myID: myID,
                            onLongPress: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { focused = message }; Haptics.light() },
                            onDoubleTap: { Task { await react(message, myReaction(message) == "👏" ? nil : "👏") } }
                        )
                        .padding(.top, startsGroup ? 8 : 2)
                        .id(message.id)
                        if message.id == lastMineID, let status = readStatus(for: message) {
                            Text(status).font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.top, 3).padding(.trailing, 4)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: messages.last?.id) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .overlay { if let focused { reactionOverlay(focused) } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { if isGroup { showsMembers = true } } label: {
                    HStack(spacing: 8) {
                        ChatAvatar(title: title, url: others.first?.avatarURL, isGroup: isGroup, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                            if isGroup {
                                Text("\(members.count) Mitglieder").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGroup ? "\(title), Mitglieder anzeigen" : title)
            }
        }
        .sheet(isPresented: $showsMembers) {
            NavigationStack { ChatMembersView(conversationID: conversationID, title: title) { dismiss() } }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Bausteine

    private static func sameGroup(_ a: ChatMessage?, _ b: ChatMessage?) -> Bool {
        guard let a, let b, a.kind != "system", b.kind != "system", a.senderID == b.senderID else { return false }
        return abs(b.createdAt.timeIntervalSince(a.createdAt)) < 180
    }

    private var lastMineID: UUID? { messages.last(where: { $0.senderID == myID && !$0.deleted })?.id }

    private func readStatus(for message: ChatMessage) -> String? {
        guard !others.isEmpty else { return nil }
        let seen = others.filter { ($0.lastReadAt ?? .distantPast) >= message.createdAt }
        if seen.count == others.count { return isGroup ? "Von allen gesehen" : "Gesehen" }
        if isGroup && !seen.isEmpty { return "Gesehen von \(seen.count)" }
        return "Zugestellt"
    }

    private func myReaction(_ message: ChatMessage) -> String? {
        message.reactions.first { $0.userID == myID }?.emoji
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ChatAvatar(title: title, url: others.first?.avatarURL, isGroup: isGroup, size: 72)
            Text(title).font(.system(.title3, design: .serif).weight(.semibold))
            Text(isGroup ? "Plant hier eure nächsten Konzertabende." : "Schreib die erste Nachricht – oder teil ein Konzert von seiner Seite aus.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(["Hast du Lust auf ein Konzert?", "Was hörst du gerade?", "Gehst du dieses Wochenende irgendwo hin?"], id: \.self) { suggestion in
                    Button { draft = suggestion; inputFocused = true } label: {
                        Text(suggestion).font(.subheadline).foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Nachricht", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 21, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.primary.opacity(0.08)) }
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(KlangradarTheme.accent, in: .circle)
                        .scaleEffect(canSend ? 1 : 0.6)
                        .opacity(canSend ? 1 : 0)
                }
                .disabled(!canSend)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: canSend)
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    /// Reaktionen: Emoji-Leiste über einem Aktionsmenü, Hintergrund abgedunkelt.
    private func reactionOverlay(_ message: ChatMessage) -> some View {
        let isMine = message.senderID == myID
        let current = myReaction(message)
        return ZStack(alignment: isMine ? .bottomTrailing : .bottomLeading) {
            Color.black.opacity(0.28).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { focused = nil } }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(ChatReactions.all, id: \.self) { emoji in
                        Button {
                            Task { await react(message, current == emoji ? nil : emoji) }
                            withAnimation(.easeOut(duration: 0.2)) { focused = nil }
                        } label: {
                            Text(emoji).font(.system(size: 28))
                                .frame(width: 44, height: 44)
                                .background(current == emoji ? KlangradarTheme.accent.opacity(0.18) : .clear, in: .circle)
                        }
                        .buttonStyle(ReactionButtonStyle())
                        .accessibilityLabel("Mit \(emoji) reagieren")
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.15), radius: 14, y: 6)

                Text(message.body ?? message.event?.title ?? "")
                    .font(.body).lineLimit(4)
                    .foregroundStyle(isMine ? .white : .primary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(isMine ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)), in: .rect(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: 280, alignment: isMine ? .trailing : .leading)

                VStack(spacing: 0) {
                    if let body = message.body {
                        overlayAction("Kopieren", "doc.on.doc") { UIPasteboard.general.string = body }
                    }
                    if isMine {
                        Divider()
                        overlayAction("Löschen", "trash", role: .destructive) { Task { await delete(message) } }
                    }
                }
                .frame(width: 220)
                .background(.regularMaterial, in: .rect(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            .transition(.scale(scale: 0.9, anchor: isMine ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
        }
    }

    private func overlayAction(_ title: String, _ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role) {
            action()
            withAnimation(.easeOut(duration: 0.2)) { focused = nil }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol)
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        async let loadedMessages = try? repository.chatThread(conversationID, token: token)
        async let loadedMembers = try? repository.chatMembers(conversationID, token: token)
        if let loaded = await loadedMessages, loaded != messages {
            withAnimation(.snappy) { messages = loaded }
            await repository.chatMarkRead(conversationID, token: token)
        }
        if let loaded = await loadedMembers { members = loaded }
        didLoad = true
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isSending = true; error = nil
        defer { isSending = false }
        draft = ""
        do {
            try await repository.chatSend(conversationID, body: text, token: token)
            Haptics.light()
            await load()
        } catch {
            draft = text
            self.error = "Nachricht konnte nicht gesendet werden."
        }
    }

    private func react(_ message: ChatMessage, _ emoji: String?) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.chatReact(message.id, emoji: emoji, token: token)
        Haptics.light()
        await load()
    }

    private func delete(_ message: ChatMessage) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.chatDelete(message.id, token: token)
        await load()
    }
}

private struct ReactionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 1.35 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let isGroupChat: Bool
    let startsGroup: Bool
    let endsGroup: Bool
    let myID: UUID?
    let onLongPress: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        if message.kind == "system" {
            Text("\(message.senderName) \(message.body ?? "")")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
        } else {
            HStack(alignment: .bottom, spacing: 6) {
                if isMine { Spacer(minLength: 56) }
                if isGroupChat && !isMine {
                    Group {
                        if endsGroup { SocialAvatar(name: message.senderName, url: message.senderAvatar, size: 28) }
                        else { Color.clear }
                    }
                    .frame(width: 28, height: 28)
                }
                VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                    if isGroupChat && !isMine && startsGroup {
                        Text(message.senderName.split(separator: " ").first.map(String.init) ?? message.senderName)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 12)
                    }
                    content
                        .contentShape(bubbleShape)
                        .onTapGesture(count: 2, perform: onDoubleTap)
                        .onLongPressGesture(minimumDuration: 0.35, perform: onLongPress)
                        .overlay(alignment: isMine ? .bottomLeading : .bottomTrailing) { reactionChips }
                        .padding(.bottom, message.reactions.isEmpty ? 0 : 12)
                }
                if !isMine { Spacer(minLength: 56) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Reagieren", onLongPress)
        }
    }

    @ViewBuilder private var reactionChips: some View {
        if !message.reactions.isEmpty {
            HStack(spacing: 2) {
                ForEach(groupedReactions, id: \.emoji) { item in
                    Text(item.emoji).font(.system(size: 13))
                    if item.count > 1 { Text("\(item.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
            .overlay { Capsule().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 2) }
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .offset(x: isMine ? -8 : 8, y: 14)
        }
    }

    private var groupedReactions: [(emoji: String, count: Int)] {
        var counts: [String: Int] = [:]
        for reaction in message.reactions { counts[reaction.emoji, default: 0] += 1 }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var fill: AnyShapeStyle {
        isMine ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
    }

    @ViewBuilder private var content: some View {
        if message.deleted {
            Label("Nachricht gelöscht", systemImage: "nosign")
                .font(.subheadline.italic()).foregroundStyle(.secondary)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.6), in: bubbleShape)
        } else if let event = message.event {
            VStack(alignment: .leading, spacing: 0) {
                ChatEventCard(event: event, isInvite: message.kind == "invite")
                if let body = message.body {
                    Text(body).font(.body).padding(.horizontal, 12).padding(.top, 9)
                        .foregroundStyle(isMine ? .white : .primary)
                }
                if endsGroup { timestamp.frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 12).padding(.top, 4) }
                Color.clear.frame(height: 8)
            }
            .frame(width: 264, alignment: .leading)
            .background(fill, in: bubbleShape)
            .clipShape(bubbleShape)
            .shadow(color: .black.opacity(isMine ? 0 : 0.05), radius: 2, y: 1)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(message.body ?? "").font(.body).foregroundStyle(isMine ? .white : .primary)
                if endsGroup { timestamp }
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(fill, in: bubbleShape)
            .shadow(color: .black.opacity(isMine ? 0 : 0.05), radius: 2, y: 1)
            .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
        }
    }

    private var timestamp: some View {
        Text(KlangradarDateTime.string(message.createdAt, format: "HH:mm"))
            .font(.caption2).monospacedDigit()
            .foregroundStyle(isMine ? Color.white.opacity(0.7) : Color.secondary)
    }

    /// Spitze nur an der letzten Blase einer Gruppe; dazwischen engere Ecken.
    private var bubbleShape: UnevenRoundedRectangle {
        let big: CGFloat = 19, small: CGFloat = 6
        return UnevenRoundedRectangle(
            topLeadingRadius: !isMine && !startsGroup ? small : big,
            bottomLeadingRadius: !isMine ? (endsGroup ? 4 : small) : big,
            bottomTrailingRadius: isMine ? (endsGroup ? 4 : small) : big,
            topTrailingRadius: isMine && !startsGroup ? small : big,
            style: .continuous)
    }
}

private struct ChatEventCard: View {
    let event: SocialEvent
    let isInvite: Bool

    var body: some View {
        Button { DeepLinkRouter.shared.handle(route: "/event/\(event.slug)") } label: {
            VStack(alignment: .leading, spacing: 0) {
                CachedAsyncImage(url: event.imageURL, maxPixel: 600) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Color(uiColor: .tertiarySystemFill).overlay { Image(systemName: "music.note").foregroundStyle(.secondary) } }
                }
                .frame(width: 260, height: 130)
                .clipped()
                .overlay(alignment: .topLeading) {
                    if isInvite {
                        Label("Einladung", systemImage: "envelope.open.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: .capsule)
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isInvite ? "Einladung" : "Konzert"): \(event.title)")
    }
}

// MARK: - Neuer Chat / Gruppe

struct NewChatSheet: View {
    let onOpen: (ChatRoute) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var isGroup = false
    @State private var selected: Set<UUID> = []
    @State private var groupName = ""
    @State private var groupIcon = "music.note.house.fill"
    @State private var query = ""
    @State private var isWorking = false

    private let icons = ["music.note.house.fill", "theatermasks.fill", "music.quarternote.3", "pianokeys", "guitars.fill", "star.fill", "heart.fill", "figure.2"]

    private var filtered: [Friend] {
        query.isEmpty ? friends : friends.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Art", selection: $isGroup) {
                        Text("Einzelchat").tag(false)
                        Text("Gruppe").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                if isGroup {
                    Section("Gruppe") {
                        TextField("Name der Gruppe", text: $groupName)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(icons, id: \.self) { icon in
                                    Button { groupIcon = icon } label: {
                                        Image(systemName: icon).font(.body.weight(.semibold))
                                            .foregroundStyle(groupIcon == icon ? .white : KlangradarTheme.accent)
                                            .frame(width: 42, height: 42)
                                            .background(groupIcon == icon ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(0.12)), in: .circle)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(icon)
                                }
                            }
                        }
                    }
                }
                Section(isGroup ? "Mitglieder wählen" : "Freund:in wählen") {
                    if friends.isEmpty {
                        Text("Füge zuerst Freunde hinzu, um zu chatten.").foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { friend in
                        Button { tap(friend) } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(name: friend.name, url: friend.avatarURL, size: 40)
                                Text(friend.name).foregroundStyle(.primary)
                                Spacer()
                                if isGroup {
                                    Image(systemName: selected.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(friend.id) ? KlangradarTheme.accent : .secondary)
                                        .font(.title3)
                                }
                            }
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .searchable(text: $query, prompt: "Freunde suchen")
            .navigationTitle(isGroup ? "Neue Gruppe" : "Neuer Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if isGroup {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Erstellen") { Task { await createGroup() } }
                            .disabled(selected.isEmpty || groupName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                    }
                }
            }
            .task {
                guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
                friends = ((try? await repository.friends(token: token)) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }
    }

    private func tap(_ friend: Friend) {
        if isGroup {
            if selected.contains(friend.id) { selected.remove(friend.id) } else { selected.insert(friend.id) }
            return
        }
        Task {
            guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
            isWorking = true
            defer { isWorking = false }
            if let id = try? await repository.chatOpenDirect(with: friend.id, token: token) {
                onOpen(ChatRoute(id: id, title: friend.name, isGroup: false))
            }
        }
    }

    private func createGroup() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isWorking = true
        defer { isWorking = false }
        let name = groupName.trimmingCharacters(in: .whitespaces)
        if let id = try? await repository.chatCreateGroup(title: name, members: Array(selected), icon: "sf:\(groupIcon)", token: token) {
            onOpen(ChatRoute(id: id, title: name, isGroup: true))
        }
    }
}

// MARK: - Mitglieder einer Gruppe

private struct ChatMembersView: View {
    let conversationID: UUID
    let title: String
    let onLeft: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var members: [ChatMember] = []
    @State private var friends: [Friend] = []
    @State private var confirmsLeave = false

    var body: some View {
        List {
            Section("\(members.count) Mitglieder") {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        SocialAvatar(name: member.name, url: member.avatarURL, size: 36)
                        Text(member.name)
                    }
                }
            }
            let addable = friends.filter { friend in !members.contains { $0.id == friend.id } }
            if !addable.isEmpty {
                Section("Freunde hinzufügen") {
                    ForEach(addable) { friend in
                        Button { Task { await add(friend) } } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(name: friend.name, url: friend.avatarURL, size: 36)
                                Text(friend.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(KlangradarTheme.accent)
                            }
                        }
                    }
                }
            }
            Section {
                Button("Gruppe verlassen", role: .destructive) { confirmsLeave = true }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        .confirmationDialog("Gruppe verlassen?", isPresented: $confirmsLeave, titleVisibility: .visible) {
            Button("Verlassen", role: .destructive) { Task { await leave() } }
        }
        .task { await load() }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        async let m = try? repository.chatMembers(conversationID, token: token)
        async let f = try? repository.friends(token: token)
        members = await m ?? []
        friends = await f ?? []
    }

    private func add(_ friend: Friend) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.chatAddMembers(conversationID, members: [friend.id], token: token)
        await load()
    }

    private func leave() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.chatLeave(conversationID, token: token)
        dismiss()
        onLeft()
    }
}

// MARK: - Konzert an Freunde senden (Konzertseite → Teilen)

struct ShareEventToFriendsSheet: View {
    let eventID: UUID
    let eventTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [ChatConversation] = []
    @State private var friends: [Friend] = []
    @State private var selectedChats: Set<UUID> = []
    @State private var selectedFriends: Set<UUID> = []
    @State private var note = ""
    @State private var asInvite = false
    @State private var isSending = false
    @State private var sent = false

    private var friendsWithoutChat: [Friend] {
        let direct = Set(conversations.compactMap(\.otherUserID))
        return friends.filter { !direct.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Als Einladung senden", isOn: $asInvite)
                    TextField("Nachricht (optional)", text: $note, axis: .vertical).lineLimit(1...3)
                } footer: {
                    Text(asInvite ? "Deine Freunde sehen „Einladung“ auf der Konzertkarte." : "Das Konzert erscheint als Karte im Chat.")
                }
                if !conversations.isEmpty {
                    Section("Chats") {
                        ForEach(conversations) { conversation in
                            row(title: conversation.title, avatar: ChatAvatar(title: conversation.title, url: conversation.avatarURL, isGroup: conversation.isGroup, icon: conversation.icon, size: 36),
                                isOn: selectedChats.contains(conversation.id)) {
                                toggle(&selectedChats, conversation.id)
                            }
                        }
                    }
                }
                if !friendsWithoutChat.isEmpty {
                    Section("Freunde") {
                        ForEach(friendsWithoutChat) { friend in
                            row(title: friend.name, avatar: SocialAvatar(name: friend.name, url: friend.avatarURL, size: 36),
                                isOn: selectedFriends.contains(friend.id)) {
                                toggle(&selectedFriends, friend.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle(eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sent ? "Gesendet" : "Senden") { Task { await send() } }
                        .disabled((selectedChats.isEmpty && selectedFriends.isEmpty) || isSending || sent)
                }
            }
            .task {
                guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
                async let c = try? repository.chatInbox(token: token)
                async let f = try? repository.friends(token: token)
                conversations = await c ?? []
                friends = (await f ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }
    }

    private func row(title: String, avatar: some View, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                avatar
                Text(title).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isOn ? KlangradarTheme.accent : .secondary)
            }
        }
    }

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func send() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isSending = true
        defer { isSending = false }
        var targets = Array(selectedChats)
        for friend in selectedFriends {
            if let id = try? await repository.chatOpenDirect(with: friend, token: token) { targets.append(id) }
        }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        for target in targets {
            try? await repository.chatSend(target, kind: asInvite ? "invite" : "event", body: text.isEmpty ? nil : text, eventID: eventID, token: token)
        }
        Haptics.confirm()
        sent = true
        try? await Task.sleep(for: .milliseconds(600))
        dismiss()
    }
}
