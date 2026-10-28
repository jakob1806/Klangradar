import SwiftUI

/// Konzertseite (kommend): Freunde, die hingehen. Planen/Fragen/Teilen
/// liegen seit 24.10.2026 im "…"-Menü oben (EventDetailView).
struct FriendsAttendingRow: View {
    let event: ConcertEvent
    let shareURL: URL?
    @EnvironmentObject private var follows: FollowStore
    @State private var friends: [Friend] = []
    @State private var composer: ComposerMode?

    private enum ComposerMode: Identifiable {
        case plan, ask
        var id: Int { self == .plan ? 0 : 1 }
    }

    private var isUpcoming: Bool { (event.startDate ?? .distantPast) > .now }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if !friends.isEmpty {
                    HStack(spacing: 10) {
                        AvatarStack(people: friends.map { SocialPerson(id: $0.id, name: $0.name, avatarURL: $0.avatarURL) }, size: 30)
                        Text("\(AvatarStack.names(friends.map { SocialPerson(id: $0.id, name: $0.name, avatarURL: $0.avatarURL) })) \(friends.count == 1 ? "geht" : "gehen") hin")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                }
            }
            .padding(.bottom, friends.isEmpty ? 0 : 20)
            // Freunde-Ausbau 28.10.2026: Ticket übrig, Privat hingehen.
            if isUpcoming && follows.isSignedIn {
                EventFriendsExtras(event: event)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            friends = await follows.friendsAttending(eventID: event.id)
            // Schnellaktion "Freunde fragen" aus einer Push-Mitteilung.
            if DeepLinkRouter.shared.pendingPlanForSlug == event.slug {
                DeepLinkRouter.shared.pendingPlanForSlug = nil
                if isUpcoming && follows.isSignedIn { composer = .ask }
            }
        }
        .sheet(item: $composer) { mode in
            NavigationStack {
                PlanComposerView(event: event, quickAsk: mode == .ask)
            }
        }
    }

    private var shareText: String {
        var lines = ["Kommst du mit? \(event.title)", event.dateLine]
        if let shareURL { lines.append(shareURL.absoluteString) }
        lines.append("Gefunden mit Klangradar")
        return lines.joined(separator: "\n")
    }
}

/// Konzertseite (vergangen): eigene Kurzbewertung und Bewertungen von Freunden.
struct EventRatingSection: View {
    let event: ConcertEvent
    @EnvironmentObject private var follows: FollowStore
    @State private var ratings: EventRatings?
    @State private var stars = 0
    @State private var comment = ""
    @State private var isEditing = false
    @State private var isSaving = false

    private var hasStarted: Bool { (event.startDate ?? .distantFuture) <= .now }

    var body: some View {
        if hasStarted && follows.isSignedIn {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wie war's?").font(.title2.bold())
                LiquidGlassSurface(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let mine = ratings?.mine, !isEditing {
                            HStack {
                                StarRating(stars: .constant(mine.stars), size: 20, editable: false)
                                Spacer()
                                Button("Ändern") { stars = mine.stars; comment = mine.comment ?? ""; isEditing = true }.font(.subheadline)
                            }
                            if let text = mine.comment { Text("„\(text)“").font(.subheadline).italic() }
                        } else {
                            Text("Deine Bewertung sehen nur deine Freunde.").font(.caption).foregroundStyle(.secondary)
                            StarRating(stars: $stars)
                            if stars > 0 {
                                TextField("Ein Satz dazu (optional)", text: $comment, axis: .vertical)
                                    .lineLimit(1...3)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: comment) { _, value in if value.count > 200 { comment = String(value.prefix(200)) } }
                                Button(isSaving ? "Speichern …" : "Bewertung speichern") { Task { await save() } }
                                    .buttonStyle(.borderedProminent)
                                    .tint(KlangradarTheme.accent)
                                    .disabled(isSaving)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let friends = ratings?.friends, !friends.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(friends) { rating in
                            HStack(alignment: .top, spacing: 10) {
                                SocialAvatar(name: rating.person.name, url: rating.person.avatarURL, size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(rating.person.name).font(.subheadline.weight(.semibold))
                                        StarRating(stars: .constant(rating.stars), size: 12, editable: false)
                                    }
                                    if let text = rating.comment { Text(text).font(.subheadline).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 20)
            .task { await load() }
        }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        ratings = try? await repository.eventRatings(event.id, token: token)
    }

    private func save() async {
        guard stars > 0, let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isSaving = true
        defer { isSaving = false }
        try? await repository.rateEvent(event.id, stars: stars, comment: comment.isEmpty ? nil : comment, token: token)
        Haptics.confirm()
        isEditing = false
        await load()
    }
}
