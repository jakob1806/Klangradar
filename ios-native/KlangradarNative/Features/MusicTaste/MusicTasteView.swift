// Erstellt von Claude Code (09.11.2026): „Dein Musikgeschmack“.
// 13.11.2026 neu: Listenansicht in Abschnitten, Empfehlungen nur für die
// gewählte Stadt, „Das hörst du“ mit Treffer-Info, Begründung je Zeile,
// Zeitraum für Last.fm, automatische Aktualisierung nach 7 Tagen.
import SwiftUI

struct MusicTasteView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository
    let contentRepository: any ContentRepository
    @EnvironmentObject private var follows: FollowStore
    @EnvironmentObject private var cityStore: CityStore

    @State private var taste: MusicTaste?
    @State private var isLoading = true
    @State private var working: String?
    @State private var error: String?
    @State private var spotify = SpotifyTaste()
    @State private var lastfmLogin = LastFMLogin()
    @State private var showsLastFM = false
    @State private var showsAllTracks = false
    @AppStorage("lastfmUsername") private var lastfmUsername = ""
    @AppStorage("lastfmPeriod") private var lastfmPeriod = "12month"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                connectCard
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
                if let taste { content(taste) }
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
        .task(id: cityStore.selectedCity?.id) { await load() }
    }

    private var cityName: String? { cityStore.selectedCity?.name }

    private func load() async {
        guard let token = auth.accessToken else { isLoading = false; return }
        taste = await repository.musicTaste(cityID: cityStore.selectedCity?.id, token: token)
        isLoading = false
        // Last.fm nach 7 Tagen still neu einlesen.
        if let taste, taste.providers.contains("lastfm"), !lastfmUsername.isEmpty,
           let updated = taste.updatedAt, updated < .now.addingTimeInterval(-7 * 86_400), working == nil {
            let name = lastfmUsername, period = lastfmPeriod, client = repository.client
            await analyze(key: "lastfm") { try await LastFMTaste.read(username: name, period: period, client: client, token: token) }
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
                Text(summary(taste)).font(.footnote).opacity(0.85)
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

    private func summary(_ taste: MusicTaste) -> String {
        let period: String = switch taste.period {
        case "1month": "der letzten 4 Wochen"
        case "6month": "der letzten 6 Monate"
        case "overall": "insgesamt"
        default: "der letzten 12 Monate"
        }
        let source = taste.providers.map { $0 == "lastfm" ? "Last.fm" : $0 == "apple_music" ? "Apple Music" : "Spotify" }.joined(separator: " & ")
        var text = "Aus \(taste.artistCount) Künstler:innen und \(taste.trackCount) Titeln \(period) · \(source)"
        if let updated = taste.updatedAt { text += " · Stand \(KlangradarDateTime.string(updated, format: "d. MMM"))" }
        return text
    }

    // MARK: Inhalt

    @ViewBuilder
    private func content(_ taste: MusicTaste) -> some View {
        let city = cityName.map { " in \($0)" } ?? ""
        section("Konzerte für dich\(city)", items: taste.events, kind: .event,
                empty: "Gerade keine passenden Konzerte\(city).")
        if taste.otherCityCount > 0, let other = taste.otherCity {
            Label("\(taste.otherCityCount) weitere passende Konzerte in anderen Städten, die meisten in \(other).", systemImage: "mappin.and.ellipse")
                .font(.footnote).foregroundStyle(.secondary)
        }
        listenedSection(taste)
        section("Deine Komponist:innen", items: sortedForFollow(taste.composers, kind: .person), kind: .person)
        section("Deine Interpret:innen & Ensembles",
                items: sortedForFollow(taste.persons.filter { p in !taste.composers.contains { $0.id == p.id } }, kind: .person)
                     + sortedForFollow(taste.ensembles, kind: .ensemble).map { $0 },
                kind: .performer(ensembleIDs: Set(taste.ensembles.map(\.id))))
        section("Werke, die du hörst", items: taste.works, kind: .work)
        section("Spielstätten\(city)", items: taste.venues, kind: .venue)
        if !taste.genres.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Genres")
                MusicGenreChips(items: Array(taste.genres.prefix(8)))
            }
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
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(KlangradarTheme.accent)
        }
    }

    /// Wem man schon folgt, rutscht nach unten (und ist markiert).
    private func sortedForFollow(_ items: [MusicTaste.Item], kind: EntityKind) -> [MusicTaste.Item] {
        items.sorted { a, b in
            let fa = follows.isFollowing(kind: kind, id: a.id), fb = follows.isFollowing(kind: kind, id: b.id)
            return fa == fb ? a.score > b.score : !fa
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.title3.bold())
    }

    enum RowKind: Hashable {
        case event, person, work, venue
        case performer(ensembleIDs: Set<UUID>)
        func entity(for id: UUID) -> EntityKind {
            switch self {
            case .event, .person: .person
            case .work: .work
            case .venue: .venue
            case .performer(let ids): ids.contains(id) ? .ensemble : .person
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [MusicTaste.Item], kind: RowKind, empty: String? = nil) -> some View {
        if !items.isEmpty || empty != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle(title)
                    Spacer()
                    if items.count > 5 {
                        NavigationLink {
                            ScrollView {
                                rowList(items, kind: kind)
                                    .padding(.horizontal, KlangradarTheme.pagePadding).padding(.vertical, 16)
                                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                            }
                            .background(Color(uiColor: .systemGroupedBackground))
                            .navigationTitle(title)
                            .navigationBarTitleDisplayMode(.inline)
                        } label: { Text("Alle \(items.count)").font(.subheadline.weight(.semibold)) }
                    }
                }
                if items.isEmpty, let empty {
                    Text(empty).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    rowList(Array(items.prefix(5)), kind: kind)
                }
            }
        }
    }

    private func rowList(_ items: [MusicTaste.Item], kind: RowKind) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, kind: kind)
                if index < items.count - 1 { Divider().padding(.leading, 70) }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func detailLine(_ item: MusicTaste.Item, kind: RowKind) -> String? {
        switch kind {
        case .event:
            return item.reasons.isEmpty ? nil
                : item.reasons == ["Passt zu deinen Genres"] ? "Passt zu deinen Genres"
                : "Weil du \(item.reasons.prefix(2).joined(separator: " und ")) hörst"
        case .person, .performer:
            guard item.upcoming > 0 else { return "Gerade keine Konzerte\(cityName.map { " in \($0)" } ?? "")" }
            return item.upcoming == 1 ? "1 Konzert\(cityName.map { " in \($0)" } ?? "")" : "\(item.upcoming) Konzerte\(cityName.map { " in \($0)" } ?? "")"
        default:
            return nil
        }
    }

    @ViewBuilder
    private func row(_ item: MusicTaste.Item, kind: RowKind) -> some View {
        let entity = kind.entity(for: item.id)
        let following = kind != .event && kind != .work && kind != .venue && follows.isFollowing(kind: entity, id: item.id)
        let label = HStack(spacing: 12) {
            Group {
                switch kind {
                case .person, .performer:
                    SocialAvatar(name: item.title, url: item.imageURL, size: 46)
                default:
                    CachedAsyncImage(url: item.imageURL, maxPixel: 200) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Color(uiColor: .tertiarySystemFill).overlay { Image(systemName: symbol(kind)).foregroundStyle(.secondary) } }
                    }
                    .frame(width: 46, height: 46).clipShape(.rect(cornerRadius: 10, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let detail = detailLine(item, kind: kind) {
                    Text(detail).font(.caption).foregroundStyle(kind == .event ? KlangradarTheme.accent : .secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            switch kind {
            case .person, .performer:
                Button {
                    Task { await follows.toggle(kind: entity, id: item.id); Haptics.confirm() }
                } label: {
                    Text(following ? "Folgst du" : "Folgen").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(following ? Color.secondary : Color.white)
                        .background(following ? Color(uiColor: .tertiarySystemFill) : KlangradarTheme.accent, in: .capsule)
                }
                .buttonStyle(.plain)
            default:
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())

        if kind == .event {
            Button { if let slug = item.slug { DeepLinkRouter.shared.handle(route: "/event/\(slug)") } } label: { label }.buttonStyle(.plain)
        } else {
            NavigationLink {
                EntityDetailView(route: EntityRoute(kind: entity, identifier: item.id.uuidString.lowercased()), repository: contentRepository)
            } label: { label }
            .buttonStyle(.plain)
        }
    }

    private func symbol(_ kind: RowKind) -> String {
        switch kind {
        case .event: "music.note"
        case .venue: "building.columns"
        case .work: "music.note.list"
        default: "person"
        }
    }

    // MARK: Das hörst du

    @ViewBuilder
    private func listenedSection(_ taste: MusicTaste) -> some View {
        if !taste.listened.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Das hörst du")
                Text("Deine meistgehörten Künstler:innen – und ob sie bei uns spielen.").font(.subheadline).foregroundStyle(.secondary)
                let shown = Array(taste.listened.prefix(showsAllTracks ? 40 : 8))
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                        listenedRow(entry)
                        if index < shown.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                if !taste.topTracks.isEmpty && showsAllTracks {
                    Text("Meistgehörte Titel").font(.subheadline.weight(.semibold)).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(taste.topTracks.prefix(15)) { track in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.subheadline).lineLimit(1)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                }
                if taste.listened.count > 8 || !taste.topTracks.isEmpty {
                    Button(showsAllTracks ? "Weniger anzeigen" : "Mehr anzeigen") { withAnimation { showsAllTracks.toggle() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func listenedRow(_ entry: MusicTaste.Listened) -> some View {
        let label = HStack(spacing: 12) {
            Text("\(entry.rank)").font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline.weight(.semibold)).foregroundStyle(entry.isMatched ? .primary : .secondary).lineLimit(1)
                if entry.isMatched {
                    let city = cityName.map { " in \($0)" } ?? ""
                    Text(entry.upcoming > 0 ? "In Klangradar · \(entry.upcoming) \(entry.upcoming == 1 ? "Konzert" : "Konzerte")\(city)" : "In Klangradar · gerade keine Konzerte\(city)")
                        .font(.caption).foregroundStyle(entry.upcoming > 0 ? KlangradarTheme.accent : .secondary)
                } else {
                    Text("Nicht in Klangradar").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if entry.isMatched { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())

        if let id = entry.personID ?? entry.ensembleID {
            NavigationLink {
                EntityDetailView(route: EntityRoute(kind: entry.personID != nil ? .person : .ensemble, identifier: id.uuidString.lowercased()), repository: contentRepository)
            } label: { label }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    // MARK: Verknüpfen

    private var connectCard: some View {
        VStack(spacing: 0) {
            connectRow(name: "Apple Music", symbol: "applelogo", tint: Color(red: 0.98, green: 0.24, blue: 0.33), key: "apple_music") {
                try await AppleMusicTaste.read()
            }
            Divider().padding(.leading, 56)
            lastFMRow
            if SpotifyTaste.clientID != nil {
                Divider().padding(.leading, 56)
                connectRow(name: "Spotify (Beta, nur Tester)", symbol: "dot.radiowaves.left.and.right", tint: Color(red: 0.12, green: 0.73, blue: 0.33), key: "spotify") {
                    try await spotify.read()
                }
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

    /// Last.fm: Spotify-Hörer:innen verbinden Spotify einmal mit Last.fm und
    /// geben hier nur ihren Last.fm-Namen ein (kein Login).
    private var lastFMRow: some View {
        let connected = taste?.providers.contains("lastfm") == true
        return Button { showsLastFM = true } label: {
            HStack(spacing: 12) {
                Text("fm").font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(Color(red: 0.84, green: 0.06, blue: 0.03), in: .rect(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Last.fm – auch für Spotify").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(connected && !lastfmUsername.isEmpty ? "Verknüpft als \(lastfmUsername) · tippen zum Aktualisieren" : "Nur Nutzername, keine Anmeldung")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if working == "lastfm" { ProgressView() } else {
                    Image(systemName: connected ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(connected ? .green : .secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
        .sheet(isPresented: $showsLastFM) { lastFMSheet }
    }

    private var lastFMSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showsLastFM = false
                        Task { await loginWithLastFM() }
                    } label: {
                        Label("Mit Last.fm anmelden", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                } footer: {
                    Text("Öffnet die Anmeldeseite von Last.fm. Noch kein Konto? Dort kannst du dich in einer Minute registrieren. Spotify verbindest du danach einmal unter last.fm → Einstellungen → Anwendungen.")
                }
                Section {
                    TextField("Last.fm-Nutzername", text: $lastfmUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Oder nur den Namen eingeben")
                } footer: {
                    Text("Klangradar liest nur dein öffentliches Hörprofil – keine Zugangsdaten.")
                }
                Section("Zeitraum") {
                    Picker("Zeitraum", selection: $lastfmPeriod) {
                        Text("4 Wochen").tag("1month")
                        Text("6 Monate").tag("6month")
                        Text("12 Monate").tag("12month")
                        Text("Gesamt").tag("overall")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Link("Last.fm öffnen", destination: URL(string: "https://www.last.fm/settings/applications")!)
                }
            }
            .navigationTitle("Last.fm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showsLastFM = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analysieren") {
                        showsLastFM = false
                        let name = lastfmUsername.trimmingCharacters(in: .whitespaces)
                        Task {
                            guard let token = auth.accessToken else { return }
                            let client = repository.client
                            let period = lastfmPeriod
                            await analyze(key: "lastfm") { try await LastFMTaste.read(username: name, period: period, client: client, token: token) }
                        }
                    }
                    .disabled(lastfmUsername.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loginWithLastFM() async {
        guard let token = auth.accessToken else { error = "Bitte melde dich zuerst an."; return }
        let client = repository.client
        let period = lastfmPeriod
        let login = lastfmLogin
        await analyze(key: "lastfm") {
            let loginToken = try await login.token(client: client)
            return try await LastFMTaste.read(loginToken: loginToken, period: period, client: client, token: token)
        }
        if let name = LastFMTaste.lastUsername { lastfmUsername = name }
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
            taste = try await repository.analyzeMusicTaste(artists: result.artists, tracks: result.tracks, providers: providers,
                                                           cityID: cityStore.selectedCity?.id, period: key == "lastfm" ? lastfmPeriod : nil, token: token)
            Haptics.confirm()
        } catch MusicTasteError.cancelled {
            // nichts
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Analyse fehlgeschlagen."
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
