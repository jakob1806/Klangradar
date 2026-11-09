// Erstellt von Claude Code (09.11.2026): „Dein Musikgeschmack“ – Spotify und
// Apple Music verknüpfen, Klangprofil, Empfehlungen in fünf Reitern.
import SwiftUI

struct MusicTasteView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository
    let contentRepository: any ContentRepository
    @EnvironmentObject private var follows: FollowStore

    @State private var taste: MusicTaste?
    @State private var isLoading = true
    @State private var working: String?
    @State private var error: String?
    @State private var tab: Tab = .events
    @State private var spotify = SpotifyTaste()

    enum Tab: String, CaseIterable, Identifiable {
        case events = "Konzerte", persons = "Personen", ensembles = "Ensembles", venues = "Orte", works = "Werke"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                connectCard
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
                if let taste, taste.matchCount > 0 || !taste.events.isEmpty {
                    profileCard(taste)
                    Picker("Empfehlungen", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    recommendations(taste)
                } else if taste != nil {
                    Text("In deiner Musik haben wir noch keine Künstler:innen, Ensembles oder Werke aus unserem Klassik-Verzeichnis gefunden. Hör ein paar Klassik-Titel und analysiere später erneut.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Klangradar liest nur deine meistgehörten Künstler:innen und Titel – keine Zugangsdaten, keine Playlists. Du kannst die Verknüpfung jederzeit trennen; dann löschen wir die Daten.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            .padding(.vertical, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Musikgeschmack")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let token = auth.accessToken { taste = await repository.musicTaste(token: token) }
            isLoading = false
        }
    }

    // MARK: Kopf

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dein Klangprofil").font(.system(.title3, design: .serif).italic())
                Spacer()
                Image(systemName: "headphones").font(.headline).opacity(0.8)
            }
            Text(headline)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if let taste, taste.artistCount > 0 {
                HStack(spacing: 0) {
                    stat("\(taste.artistCount)", "Künstler:innen gehört")
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 30).padding(.horizontal, 12)
                    stat("\(taste.matchCount)", "Treffer bei uns")
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 30).padding(.horizontal, 12)
                    stat("\(taste.events.count)", "Konzerte für dich")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.20), Color(red: 0.27, green: 0.20, blue: 0.45), Color(red: 0.12, green: 0.42, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 28, style: .continuous))
    }

    private var headline: String {
        if isLoading { return "Einen Moment …" }
        guard let taste else { return "Was hörst du, wenn niemand zuhört?" }
        if let top = taste.composers.first?.title ?? taste.persons.first?.title { return "Viel \(top) – und mehr" }
        return "Dein Profil ist bereit"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).opacity(0.8)
        }
    }

    // MARK: Verknüpfen

    private var connectCard: some View {
        VStack(spacing: 0) {
            connectRow(name: "Apple Music", symbol: "applelogo", tint: Color(red: 0.98, green: 0.24, blue: 0.33), key: "apple_music") {
                try await AppleMusicTaste.read()
            }
            Divider().padding(.leading, 56)
            connectRow(name: "Spotify", symbol: "dot.radiowaves.left.and.right", tint: Color(red: 0.12, green: 0.73, blue: 0.33), key: "spotify") {
                try await spotify.read()
            }
            if taste != nil {
                Divider().padding(.leading, 56)
                Button(role: .destructive) {
                    Task {
                        guard let token = auth.accessToken else { return }
                        await repository.disconnectMusicTaste(token: token)
                        taste = nil
                    }
                } label: {
                    HStack { Image(systemName: "link.badge.minus").frame(width: 28); Text("Verknüpfung trennen und Daten löschen"); Spacer() }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func connectRow(name: String, symbol: String, tint: Color, key: String,
                            read: @escaping @MainActor () async throws -> (artists: [ListenedArtist], tracks: [ListenedTrack])) -> some View {
        let connected = taste?.providers.contains(key) == true
        return Button {
            Task { await analyze(key: key, read: read) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(tint, in: .rect(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(connected ? "Verknüpft · tippen zum Aktualisieren" : "Verknüpfen und analysieren").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if working == key { ProgressView() } else {
                    Image(systemName: connected ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(connected ? .green : .secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
    }

    private func analyze(key: String, read: @MainActor () async throws -> (artists: [ListenedArtist], tracks: [ListenedTrack])) async {
        guard let token = auth.accessToken else { error = "Bitte melde dich zuerst an."; return }
        working = key; error = nil
        defer { working = nil }
        do {
            let result = try await read()
            guard !result.artists.isEmpty || !result.tracks.isEmpty else { error = "In deiner Mediathek haben wir nichts gefunden."; return }
            let providers = Array(Set((taste?.providers ?? []) + [key]))
            taste = try await repository.analyzeMusicTaste(artists: result.artists, tracks: result.tracks, providers: providers, token: token)
            Haptics.confirm()
        } catch MusicTasteError.cancelled {
            // nichts
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Analyse fehlgeschlagen."
        }
    }

    // MARK: Profil

    private func profileCard(_ taste: MusicTaste) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !taste.composers.isEmpty {
                Text("DEINE KOMPONIST:INNEN").font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(taste.composers.prefix(10)) { item in
                            NavigationLink { EntityDetailView(route: EntityRoute(kind: .person, identifier: item.id.uuidString.lowercased()), repository: contentRepository) } label: {
                                VStack(spacing: 6) {
                                    SocialAvatar(name: item.title, url: item.imageURL, size: 58)
                                    Text(item.title.split(separator: " ").last.map(String.init) ?? item.title)
                                        .font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                }
                                .frame(width: 70)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !taste.genres.isEmpty {
                Text("GENRES").font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
                MusicGenreChips(items: Array(taste.genres.prefix(8)))
            }
            if !taste.persons.isEmpty || !taste.ensembles.isEmpty {
                Button {
                    Task {
                        for item in taste.persons.prefix(15) where !follows.isFollowing(kind: .person, id: item.id) {
                            await follows.toggle(kind: .person, id: item.id)
                        }
                        for item in taste.ensembles.prefix(10) where !follows.isFollowing(kind: .ensemble, id: item.id) {
                            await follows.toggle(kind: .ensemble, id: item.id)
                        }
                        Haptics.confirm()
                    }
                } label: {
                    Label("Allen Treffern folgen", systemImage: "person.badge.plus").font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func recommendations(_ taste: MusicTaste) -> some View {
        let items: [MusicTaste.Item] = switch tab {
        case .events: taste.events
        case .persons: taste.persons
        case .ensembles: taste.ensembles
        case .venues: taste.venues
        case .works: taste.works
        }
        if items.isEmpty {
            Text("Hier gibt es noch nichts Passendes.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(30).enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < min(items.count, 30) - 1 { Divider().padding(.leading, 70) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private func row(_ item: MusicTaste.Item) -> some View {
        let label = HStack(spacing: 12) {
            Group {
                if tab == .events || tab == .venues || tab == .works {
                    CachedAsyncImage(url: item.imageURL, maxPixel: 200) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Color(uiColor: .tertiarySystemFill).overlay { Image(systemName: tabSymbol).foregroundStyle(.secondary) } }
                    }
                    .frame(width: 46, height: 46).clipShape(.rect(cornerRadius: 10, style: .continuous))
                } else {
                    SocialAvatar(name: item.title, url: item.imageURL, size: 46)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())

        switch tab {
        case .events:
            Button { if let slug = item.slug { DeepLinkRouter.shared.handle(route: "/event/\(slug)") } } label: { label }.buttonStyle(.plain)
        default:
            NavigationLink {
                EntityDetailView(route: EntityRoute(kind: entityKind, identifier: item.id.uuidString.lowercased()), repository: contentRepository)
            } label: { label }
            .buttonStyle(.plain)
        }
    }

    private var entityKind: EntityKind {
        switch tab {
        case .persons, .events: .person
        case .ensembles: .ensemble
        case .venues: .venue
        case .works: .work
        }
    }

    private var tabSymbol: String {
        switch tab {
        case .events: "music.note"
        case .venues: "building.columns"
        case .works: "music.note.list"
        default: "person"
        }
    }
}

/// Einfache umbrechende Chips.
private struct MusicGenreChips: View {
    let items: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(items) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { chips(Array(items.prefix(4))) }
                HStack(spacing: 6) { chips(Array(items.dropFirst(4))) }
            }
        }
    }

    @ViewBuilder private func chips(_ list: [String]) -> some View {
        ForEach(list, id: \.self) { item in
            Text(item.capitalized).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
        }
    }
}
