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
                                card("Passt zu euch beiden", caption: "Aus euren gemeinsamen Interessen, gefolgten Künstler:innen und Merklisten.", events: matches)
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
    }

    private func header(_ profile: UserProfile) -> some View {
        VStack(spacing: 14) {
            SocialAvatar(name: profile.person.name, url: profile.person.avatarURL, size: 104)
                .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3) }
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            VStack(spacing: 4) {
                Text(profile.person.name).font(.system(.title, design: .serif).weight(.semibold))
                if profile.isFriend {
                    HStack(spacing: 10) {
                        Label(profile.isClose ? "Enge:r Freund:in" : "Befreundet", systemImage: profile.isClose ? "star.fill" : "person.2.fill")
                        if profile.isMuted { Label("Stumm", systemImage: "bell.slash.fill").foregroundStyle(.secondary) }
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                }
            }
            if let match = profile.tasteMatch {
                tasteMatchBadge(match)
            }
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if profile.visible {
                HStack(spacing: 0) {
                    stat(profile.concerts, profile.concerts == 1 ? "Konzert" : "Konzerte")
                    Divider().frame(height: 30)
                    stat(profile.friends, "Freunde")
                    Divider().frame(height: 30)
                    stat(profile.mutualFriends, "Gemeinsam")
                }
                .padding(.vertical, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
            }
            if !profile.isFriend {
                RelationButton(person: profile.person, source: "profile") { _ in Task { await load() } }
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(alignment: .top) {
            LinearGradient(colors: [KlangradarTheme.accent.opacity(0.28), KlangradarTheme.accent.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .ignoresSafeArea(edges: .top)
        }
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
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.thinMaterial, in: .capsule)
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

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { isLoading = false; return }
        profile = try? await repository.userProfile(userID, token: token)
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
