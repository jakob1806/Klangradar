import SwiftUI

/// Profil eines anderen Nutzers (Freund oder öffentliches Profil).
struct UserProfileView: View {
    let userID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?
    @State private var matches: [SocialEvent] = []
    @State private var together: [SocialEvent] = []
    @State private var isLoading = true
    @State private var confirmsRemove = false
    @State private var confirmsBlock = false
    @State private var showsReport = false
    @State private var reportSent = false

    private var year: Int { KlangradarDateTime.calendar.component(.year, from: .now) }

    var body: some View {
        Group {
            if let profile {
                List {
                    Section { header(profile) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                    if profile.visible {
                        if !profile.topComposers.isEmpty {
                            Section("Hört am liebsten") {
                                FlowChips(items: profile.topComposers)
                            }
                        }
                        if profile.isFriend && !together.isEmpty {
                            Section("Gemeinsam erlebt \(String(year))") {
                                ForEach(together) { SocialEventRow(event: $0) }
                            }
                        }
                        if !profile.upcoming.isEmpty {
                            Section("Geht demnächst zu") {
                                ForEach(profile.upcoming) { SocialEventRow(event: $0) }
                            }
                        }
                        if profile.isFriend && !matches.isEmpty {
                            Section {
                                ForEach(matches) { SocialEventRow(event: $0) }
                            } header: {
                                Text("Passt zu euch beiden")
                            } footer: {
                                Text("Aus euren gemeinsamen Interessen, gefolgten Künstler:innen und Merklisten.")
                            }
                        }
                    } else {
                        Section {
                            Label("Dieses Profil ist privat. Sobald ihr befreundet seid, seht ihr gegenseitig eure geplanten Konzerte.", systemImage: "lock")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if profile.isFriend {
                                Button("Freundschaft beenden", systemImage: "person.badge.minus", role: .destructive) { confirmsRemove = true }
                            }
                            Button("Blockieren", systemImage: "hand.raised", role: .destructive) { confirmsBlock = true }
                            Button("Melden", systemImage: "exclamationmark.bubble") { showsReport = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
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
        VStack(spacing: 12) {
            SocialAvatar(name: profile.person.name, url: profile.person.avatarURL, size: 96)
            Text(profile.person.name).font(.title2.bold())
            if let bio = profile.bio { Text(bio).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if profile.visible {
                HStack(spacing: 0) {
                    stat(profile.concerts, "Konzerte")
                    Divider().frame(height: 30)
                    stat(profile.friends, "Freunde")
                    Divider().frame(height: 30)
                    stat(profile.mutualFriends, "Gemeinsam")
                }
                .padding(.vertical, 6)
            }
            if !profile.isFriend {
                RelationButton(person: profile.person, source: "profile") { _ in Task { await load() } }
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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
            async let matchRows = try? repository.friendMatchEvents(userID, token: token)
            async let togetherRows = try? repository.sharedConcerts(with: userID, year: year, token: token)
            matches = await matchRows ?? []
            together = await togetherRows ?? []
        }
        isLoading = false
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
