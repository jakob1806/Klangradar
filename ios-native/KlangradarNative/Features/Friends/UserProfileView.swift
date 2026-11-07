import SwiftUI

/// Profil eines anderen Nutzers (Freund oder öffentliches Profil).
/// Neu gestaltet 27.10.2026 (Claude Code): Kopf mit Verlauf, gemeinsamer
/// Geschmack hervorgehoben, Konzerte als Karten statt Liste.
struct UserProfileView: View {
    let userID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?
    @State private var matches: [SocialEvent] = []
    @State private var isLoading = true
    @State private var confirmsRemove = false
    @State private var confirmsBlock = false
    @State private var showsReport = false
    @State private var reportSent = false

    /// Lieblingskomponist:innen, die ihr beide teilt (seit 000129 vom Server).
    private var sharedComposers: [String] {
        guard let profile else { return [] }
        let shared = Set(profile.sharedComposers.map { $0.lowercased() })
        return profile.topComposers.filter { shared.contains($0.lowercased()) }
    }

    private var firstName: String {
        guard let name = profile?.person.name else { return "" }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    var body: some View {
        Group {
            if let profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(profile)
                        if profile.isFriend {
                            SharedYearCard(friendID: profile.person.id, friendName: profile.person.name)
                        }
                        if profile.visible {
                            if !profile.topComposers.isEmpty { tasteCard(profile) }
                            if !profile.upcoming.isEmpty {
                                card("Geht demnächst zu", caption: profile.isFriend ? "Mit „Ich komme mit“ plant ihr den Abend gemeinsam." : nil,
                                     events: profile.upcoming, joining: profile.isFriend ? profile.person : nil)
                            }
                            if profile.isFriend && !matches.isEmpty {
                                matchList(matches)
                            }
                            if profile.isFriend && !profile.sharedHistory.isEmpty {
                                card("Ihr wart beide dort", caption: historyCaption(profile), events: profile.sharedHistory)
                            }
                            if !profile.ratings.isEmpty { ratingsCard(profile) }
                            if profile.upcoming.isEmpty && matches.isEmpty && profile.sharedHistory.isEmpty {
                                Label("\(profile.person.name.split(separator: " ").first.map(String.init) ?? profile.person.name) hat gerade keine Konzerte vorgemerkt.", systemImage: "music.note")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .padding(.horizontal, KlangradarTheme.pagePadding)
                            }
                        } else {
                            Label("Dieses Profil ist privat. Sobald ihr befreundet seid, seht ihr gegenseitig eure geplanten Konzerte.", systemImage: "lock")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal, KlangradarTheme.pagePadding)
                        }
                    }
                    .padding(.bottom, 30)
                    .frame(maxWidth: KlangradarTheme.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .background { KlangradarBackground().ignoresSafeArea() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if profile.isFriend {
                                Button(profile.isClose ? "Aus engen Freunden entfernen" : "Zu engen Freunden", systemImage: profile.isClose ? "star.slash" : "star") {
                                    Task { await setClose(!profile.isClose) }
                                }
                                Button(profile.isMuted ? "Stummschaltung aufheben" : "Stummschalten", systemImage: profile.isMuted ? "bell" : "bell.slash") {
                                    Task { await setMuted(!profile.isMuted) }
                                }
                                Divider()
                                Button("Freundschaft beenden", systemImage: "person.badge.minus", role: .destructive) { confirmsRemove = true }
                            }
                            Button("Blockieren", systemImage: "hand.raised", role: .destructive) { confirmsBlock = true }
                            Button("Melden", systemImage: "exclamationmark.bubble") { showsReport = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Weitere Aktionen")
                    }
                }
                .confirmationDialog("Freundschaft mit \(profile.person.name) beenden?", isPresented: $confirmsRemove, titleVisibility: .visible) {
                    Button("Beenden", role: .destructive) { Task { await remove() } }
                }
                .confirmationDialog("\(profile.person.name) blockieren?", isPresented: $confirmsBlock, titleVisibility: .visible) {
                    Button("Blockieren", role: .destructive) { Task { await block() } }
                } message: {
                    Text("Ihr seid danach nicht mehr befreundet und könnt euch weder finden noch einladen.")
                }
                .confirmationDialog("Warum möchtest du \(profile.person.name) melden?", isPresented: $showsReport, titleVisibility: .visible) {
                    Button("Spam") { Task { await report("spam") } }
                    Button("Unangemessener Inhalt") { Task { await report("inappropriate") } }
                    Button("Gibt sich als jemand anderes aus") { Task { await report("impersonation") } }
                    Button("Anderer Grund") { Task { await report("other") } }
                }
                .alert("Danke für deine Meldung", isPresented: $reportSent) { Button("OK", role: .cancel) {} } message: {
                    Text("Die Redaktion prüft das Profil.")
                }
            } else if isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("Profil nicht verfügbar", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle(profile?.person.name ?? "Profil")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // 07.11.2026: kompakter Kopf wie bei Instagram – Bild links, rechts
    // Name, Status und Zahlen in einer Reihe; Match und Bio darunter.
    private func header(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                SocialAvatar(name: profile.person.name, url: profile.person.avatarURL, size: 88)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.person.name).font(.system(.title2, design: .serif).weight(.semibold)).lineLimit(2)
                        // 07.11.2026: „Befreundet“ entfernt; nur Sonderstatus zeigen.
                        if profile.isFriend && (profile.isClose || profile.isMuted) {
                            HStack(spacing: 8) {
                                if profile.isClose { Label("Enge:r Freund:in", systemImage: "star.fill") }
                                if profile.isMuted { Label("Stumm", systemImage: "bell.slash.fill").foregroundStyle(.secondary) }
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                        }
                    }
                    if profile.visible {
                        HStack(spacing: 18) {
                            stat(profile.concerts, profile.concerts == 1 ? "Konzert" : "Konzerte")
                            stat(profile.friends, "Freunde")
                            stat(profile.mutualFriends, "gemeinsam")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).foregroundStyle(.secondary)
            }
            if let match = profile.tasteMatch {
                tasteMatchBadge(match)
            }
            if !profile.isFriend {
                RelationButton(person: profile.person, source: "profile") { _ in Task { await load() } }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// Geschmacks-Match in Prozent (Kosinus über gefolgte Künstler:innen,
    /// Genres und Komponist:innen besuchter Konzerte, berechnet in user_profile).
    private func tasteMatchBadge(_ match: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(KlangradarTheme.accent.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: CGFloat(match) / 100)
                    .stroke(KlangradarTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(match) % Geschmacks-Match").font(.subheadline.weight(.semibold))
                Text(match >= 60 ? "Ihr hört sehr ähnlich." : match >= 30 ? "Ihr habt einiges gemeinsam." : "Ihr könnt euch Neues zeigen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func historyCaption(_ profile: UserProfile) -> String {
        let count = profile.sharedHistory.count
        return count == 1 ? "Euer gemeinsames Konzert" : "\(count) gemeinsame Konzerte, das neueste zuerst"
    }

    private func ratingsCard(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("So fand \(firstName) es").font(.system(.title3, design: .serif).weight(.semibold))
                .padding(.horizontal, KlangradarTheme.pagePadding)
            VStack(spacing: 0) {
                ForEach(profile.ratings) { rating in
                    VStack(alignment: .leading, spacing: 6) {
                        SocialEventRow(event: rating.event)
                        HStack(alignment: .top, spacing: 8) {
                            StarRating(stars: .constant(rating.stars), size: 13, editable: false)
                            if let comment = rating.comment {
                                Text("„\(comment)“").font(.subheadline).italic().foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 68)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if rating.id != profile.ratings.last?.id { Divider().padding(.leading, 82) }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.8), in: .rect(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, KlangradarTheme.pagePadding)
        }
    }

    private func tasteCard(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hört am liebsten").font(.system(.title3, design: .serif).weight(.semibold))
            if !sharedComposers.isEmpty {
                Label(sharedComposers.count == 1 ? "Ihr teilt eine Vorliebe für \(sharedComposers[0])." : "Ihr teilt \(sharedComposers.count) Lieblingskomponist:innen.", systemImage: "heart.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(KlangradarTheme.accent)
            }
            FlowLayout(spacing: 8) {
                ForEach(profile.topComposers, id: \.self) { item in
                    let shared = sharedComposers.contains(item)
                    Label(item, systemImage: shared ? "heart.fill" : "music.note")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(shared ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(KlangradarTheme.accent.opacity(0.12)), in: .capsule)
                        .foregroundStyle(shared ? AnyShapeStyle(.white) : AnyShapeStyle(KlangradarTheme.accent))
                }
            }
        }
        .padding(.horizontal, KlangradarTheme.pagePadding)
    }

    private func card(_ title: String, caption: String?, events: [SocialEvent], joining friend: SocialPerson? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.title3, design: .serif).weight(.semibold))
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            VStack(spacing: 0) {
                ForEach(events) { event in
                    SocialEventRow(event: event, trailing: friend.map { AnyView(JoinFriendButton(event: event, friend: $0)) })
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    if event.id != events.last?.id { Divider().padding(.leading, 82) }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.8), in: .rect(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, KlangradarTheme.pagePadding)
        }
    }

    /// „Passt zu euch beiden“ im üblichen Listenformat (07.11.2026).
    private func matchList(_ events: [SocialEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Passt zu euch beiden").font(.system(.title3, design: .serif).weight(.semibold))
                Text("Aus euren gemeinsamen Interessen, gefolgten Künstler:innen und Merklisten.").font(.caption).foregroundStyle(.secondary)
            }
            ConcertRowList(items: events.compactMap(\.concertEvent)) { event in
                Button { DeepLinkRouter.shared.handle(route: "/event/\(event.slug)") } label: {
                    ConcertRow(event: event)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KlangradarTheme.pagePadding)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.title3.bold()).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { isLoading = false; return }
        // Beim Aktualisieren den alten Stand behalten, falls der Abruf scheitert.
        if let loaded = try? await repository.userProfile(userID, token: token) { profile = loaded }
        if profile?.isFriend == true {
            matches = (try? await repository.friendMatchEvents(userID, token: token)) ?? []
        }
        isLoading = false
    }

    private func setClose(_ close: Bool) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        guard (try? await repository.setCloseFriend(userID, close: close, token: token)) != nil else { return }
        Haptics.confirm()
        profile?.isClose = close
    }

    private func setMuted(_ muted: Bool) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        guard (try? await repository.setFriendMuted(userID, muted: muted, token: token)) != nil else { return }
        Haptics.confirm()
        profile?.isMuted = muted
    }

    private func remove() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.removeFriend(userID, token: token)
        await SocialStore.shared.refresh()
        dismiss()
    }

    private func block() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.blockUser(userID, token: token)
        await SocialStore.shared.refresh()
        dismiss()
    }

    private func report(_ reason: String) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.reportUser(userID, reason: reason, token: token)
        reportSent = true
    }
}

/// Umbrechende Chips (z. B. Lieblingskomponist:innen).
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
                    .foregroundStyle(KlangradarTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}
