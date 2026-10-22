import SwiftUI

/// Rundes Profilbild mit Initiale als Platzhalter (einheitlich in allen Social-Ansichten).
struct SocialAvatar: View {
    let name: String
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        CachedAsyncImage(url: url, maxPixel: size * 3) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(KlangradarTheme.accent.opacity(0.14))
                    Text(initials).font(.system(size: size * 0.38, weight: .semibold, design: .rounded)).foregroundStyle(KlangradarTheme.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Überlappende Avatare ("Anna, Tom und 2 weitere").
struct AvatarStack: View {
    let people: [SocialPerson]
    var size: CGFloat = 28
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(people.prefix(limit)) { person in
                SocialAvatar(name: person.name, url: person.avatarURL, size: size)
                    .overlay { Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2) }
            }
            if people.count > limit {
                Text("+\(people.count - limit)")
                    .font(.caption2.bold())
                    .frame(width: size, height: size)
                    .background(Color(uiColor: .secondarySystemBackground), in: .circle)
                    .overlay { Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2) }
            }
        }
    }

    static func names(_ people: [SocialPerson]) -> String {
        let first = people.prefix(2).map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        switch people.count {
        case 0: return ""
        case 1: return first[0]
        case 2: return "\(first[0]) und \(first[1])"
        default: return "\(first[0]), \(first[1]) und \(people.count - 2) weitere"
        }
    }
}

/// Konzertzeile mit Bild, Titel und Termin (Pläne, Profile, Feed).
struct SocialEventRow: View {
    let event: SocialEvent
    var trailing: AnyView? = nil

    var body: some View {
        Button {
            DeepLinkRouter.shared.handle(route: "/event/\(event.slug)")
        } label: {
            HStack(spacing: 12) {
                CachedAsyncImage(url: event.imageURL, maxPixel: 240) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Color.secondary.opacity(0.12).overlay { Image(systemName: "music.note").foregroundStyle(.secondary) } }
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                    Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let note = event.note { Text(note).font(.caption).foregroundStyle(KlangradarTheme.accent).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Sterne-Anzeige bzw. -Eingabe.
struct StarRating: View {
    @Binding var stars: Int
    var size: CGFloat = 28
    var editable = true

    var body: some View {
        HStack(spacing: size * 0.18) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= stars ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(value <= stars ? Color.orange : Color.secondary.opacity(0.4))
                    .onTapGesture {
                        guard editable else { return }
                        Haptics.light()
                        withAnimation(.spring(duration: 0.25)) { stars = value }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(stars) von 5 Sternen")
        .accessibilityAdjustableAction { direction in
            guard editable else { return }
            switch direction {
            case .increment: stars = min(5, stars + 1)
            case .decrement: stars = max(1, stars - 1)
            @unknown default: break
            }
        }
    }
}

/// Button je nach Beziehung: Hinzufügen / Angefragt / Annehmen / Befreundet.
struct RelationButton: View {
    let person: SocialPerson
    let source: String
    var onChange: ((RelationStatus) -> Void)? = nil
    @State private var status: RelationStatus
    @State private var isWorking = false

    init(person: SocialPerson, source: String, onChange: ((RelationStatus) -> Void)? = nil) {
        self.person = person
        self.source = source
        self.onChange = onChange
        _status = State(initialValue: person.status)
    }

    var body: some View {
        Group {
            switch status {
            case .friend:
                Label("Befreundet", systemImage: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            case .requested:
                Button("Angefragt") { Task { await act { try await $0.cancelFriendRequest(to: person.id, token: $1); return .none } } }
                    .buttonStyle(.bordered).tint(.secondary)
            case .incoming:
                Button("Annehmen") { Task { await act { try await $0.respondFriendRequest(from: person.id, accept: true, token: $1); return .friend } } }
                    .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
            case .blocked:
                EmptyView()
            case .none:
                Button("Hinzufügen", systemImage: "person.badge.plus") {
                    Task { await act { try await $0.sendFriendRequest(to: person.id, source: source, token: $1) } }
                }
                .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
            }
        }
        .controlSize(.small)
        .disabled(isWorking)
        .animation(.snappy, value: status)
    }

    private func act(_ work: (UserRepository, String) async throws -> RelationStatus) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isWorking = true
        defer { isWorking = false }
        if let new = try? await work(repository, token) {
            Haptics.confirm()
            status = new
            onChange?(new)
            await SocialStore.shared.refresh()
        }
    }
}

/// Freundeauswahl (Pläne, Listen teilen).
struct FriendPicker: View {
    @Binding var selection: Set<UUID>
    var excluded: Set<UUID> = []
    @State private var friends: [Friend] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if available.isEmpty {
                ContentUnavailableView("Noch keine Freunde", systemImage: "person.2", description: Text("Füge Freunde im Profil unter „Freunde“ hinzu."))
            } else {
                ForEach(available) { friend in
                    Button {
                        Haptics.light()
                        if selection.contains(friend.id) { selection.remove(friend.id) } else { selection.insert(friend.id) }
                    } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(name: friend.name, url: friend.avatarURL, size: 36)
                            Text(friend.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selection.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selection.contains(friend.id) ? KlangradarTheme.accent : Color.secondary.opacity(0.5))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            if let repository = SocialStore.shared.repository, let token = SocialStore.shared.token {
                friends = (try? await repository.friends(token: token)) ?? []
            }
            isLoading = false
        }
    }

    private var available: [Friend] { friends.filter { !excluded.contains($0.id) } }
}

extension Date {
    /// "vor 3 Std.", "gestern" …
    var socialRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
