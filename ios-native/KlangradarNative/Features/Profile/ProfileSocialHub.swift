import SwiftUI

struct KlangLevel: Sendable {
    let number: Int
    let title: String
    let minimumXP: Int
    let nextXP: Int?

    static let stages = [
        KlangLevel(number: 1, title: "Auftakt", minimumXP: 0, nextXP: 100),
        KlangLevel(number: 2, title: "Zuhörer", minimumXP: 100, nextXP: 300),
        KlangLevel(number: 3, title: "Entdecker", minimumXP: 300, nextXP: 800),
        KlangLevel(number: 4, title: "Kenner", minimumXP: 800, nextXP: 1_800),
        KlangLevel(number: 5, title: "Connaisseur", minimumXP: 1_800, nextXP: 5_000),
        KlangLevel(number: 6, title: "Klangexperte", minimumXP: 5_000, nextXP: 10_000),
        KlangLevel(number: 7, title: "Maestro", minimumXP: 10_000, nextXP: nil)
    ]

    static func forXP(_ xp: Int) -> KlangLevel {
        stages.last(where: { xp >= $0.minimumXP }) ?? stages[0]
    }
}

enum FollowedProfileKind: String, Sendable {
    case person, ensemble, venue
    var title: String { switch self { case .person: "Personen"; case .ensemble: "Ensembles"; case .venue: "Orte" } }
    var entityKind: EntityKind { switch self { case .person: .person; case .ensemble: .ensemble; case .venue: .venue } }
    static let allVisible: [FollowedProfileKind] = [.person, .ensemble, .venue]
}

struct FollowedProfile: Identifiable, Sendable {
    let id: UUID
    let kind: FollowedProfileKind
    let name: String
    let slug: String?
    let imageURL: URL?
}

struct VisitedWork: Sendable, Hashable {
    let id: UUID
    let title: String
    let composerID: UUID?
    let composerName: String?
    let compositionYear: Int?
}

struct VisitedConcert: Identifiable, Sendable {
    let id: UUID
    let title: String
    let venueID: UUID?
    let venue: String
    let city: String?
    let attendedAt: Date?
    let genres: [String]
    let works: [VisitedWork]
}

struct KlangAchievement: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let progress: Int
    let target: Int
    var isUnlocked: Bool { progress >= target }
}

struct ProfileSocialSummary: Sendable {
    let visits: [VisitedConcert]
    let followed: [FollowedProfile]
    let savedEvents: Int

    static let empty = ProfileSocialSummary(visits: [], followed: [], savedEvents: 0)
    var visitedConcerts: Int { visits.count }
    var followedPeople: Int { followed.filter { $0.kind == .person || $0.kind == .ensemble }.count }
    var uniqueWorks: Set<UUID> { Set(visits.flatMap(\.works).map(\.id)) }
    var uniqueComposers: Set<UUID> { Set(visits.flatMap(\.works).compactMap(\.composerID)) }
    var uniqueVenues: Set<UUID> { Set(visits.compactMap(\.venueID)) }
    var uniqueCities: Set<String> { Set(visits.compactMap(\.city)) }
    var xp: Int { savedEvents * 2 + visitedConcerts * 15 + uniqueWorks.count * 8 + uniqueComposers.count * 5 + uniqueVenues.count * 10 }
    var level: Int { KlangLevel.forXP(xp).number }
    var levelStage: KlangLevel { KlangLevel.forXP(xp) }
    var progressToNext: Double {
        guard let next = levelStage.nextXP else { return 1 }
        return Double(xp - levelStage.minimumXP) / Double(next - levelStage.minimumXP)
    }
    var xpToNext: Int { max(0, (levelStage.nextXP ?? xp) - xp) }
    var genreCounts: [(String, Int)] {
        Dictionary(grouping: visits.flatMap(\.genres), by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }
    var achievements: [KlangAchievement] {
        let works = visits.flatMap(\.works)
        let mahler = Set(works.filter { $0.composerName?.localizedCaseInsensitiveContains("Mahler") == true }.map(\.id)).count
        let mozart = Set(works.filter { $0.composerName?.localizedCaseInsensitiveContains("Mozart") == true }.map(\.id)).count
        let newMusic = Set(works.filter { ($0.compositionYear ?? 0) > 2000 }.map(\.id)).count
        let munichVenues = Set(visits.filter { $0.city == "München" }.compactMap(\.venueID)).count
        let premieres = visits.filter { $0.title.localizedCaseInsensitiveContains("Uraufführung") || $0.title.localizedCaseInsensitiveContains("Premiere") }.count
        let operaVenues = Set(visits.filter { $0.genres.contains(where: { $0.localizedCaseInsensitiveContains("Oper") }) }.compactMap(\.venueID)).count
        return [
            .init(id: "mahler", title: "Mahler-Marathon", detail: "5 verschiedene Mahler-Werke live", symbol: "waveform.path", progress: mahler, target: 5),
            .init(id: "opera", title: "Opernentdecker", detail: "5 verschiedene Opernhäuser", symbol: "theatermasks.fill", progress: operaVenues, target: 5),
            .init(id: "new", title: "Neue Klänge", detail: "10 Werke nach 2000", symbol: "sparkles", progress: newMusic, target: 10),
            .init(id: "mozart", title: "Mozart-Kenner", detail: "15 verschiedene Mozart-Werke", symbol: "music.quarternote.3", progress: mozart, target: 15),
            .init(id: "munich", title: "München komplett", detail: "10 Münchner Spielstätten", symbol: "building.columns.fill", progress: munichVenues, target: 10),
            .init(id: "cities", title: "Weltenbummler", detail: "Konzerte in 5 Städten", symbol: "globe.europe.africa.fill", progress: uniqueCities.count, target: 5),
            .init(id: "premiere", title: "Premierenjäger", detail: "3 Premieren oder Uraufführungen", symbol: "star.fill", progress: premieres, target: 3)
        ]
    }
}

extension UserRepository {
    func socialProfileSummary(userID: UUID, token: String) async -> ProfileSocialSummary {
        async let visitsResult = try? visitedConcerts(userID: userID, token: token)
        async let followsResult = followedProfiles(userID: userID, token: token)
        async let savedResult = try? savedEventCount(userID: userID, token: token)
        return await ProfileSocialSummary(visits: visitsResult ?? [], followed: followsResult, savedEvents: savedResult ?? 0)
    }

    func savedEventCount(userID: UUID, token: String) async throws -> Int {
        let rows: [JSONObject] = try await client.get(table: "favorites", queryItems: [URLQueryItem(name: "select", value: "event_id"), URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")], accessToken: token)
        return rows.count
    }

    func visitedConcerts(userID: UUID, token: String) async throws -> [VisitedConcert] {
        let selection = "event_id,attended_at,created_at,events(title,venues(id,name,address_city),event_genres(genres(label_de)),event_works(works(id,title,composition_year,composer:persons(id,full_name))))"
        let rows: [JSONObject] = try await client.get(table: "coach_event_reflections", queryItems: [
            URLQueryItem(name: "select", value: selection), URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"), URLQueryItem(name: "order", value: "attended_at.desc.nullslast,created_at.desc")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("event_id").flatMap(UUID.init(uuidString:)), let event = row.object("events") else { return nil }
            let venue = event.object("venues")
            let genres = event.objects("event_genres").compactMap { $0.object("genres")?.string("label_de") }
            let works = event.objects("event_works").compactMap { relation -> VisitedWork? in
                guard let work = relation.object("works"), let workID = work.string("id").flatMap(UUID.init(uuidString:)) else { return nil }
                let composer = work.object("composer")
                return VisitedWork(id: workID, title: work.string("title") ?? "Werk", composerID: composer?.string("id").flatMap(UUID.init(uuidString:)), composerName: composer?.string("full_name"), compositionYear: work.integer("composition_year"))
            }
            return VisitedConcert(id: id, title: event.string("title") ?? "Konzert", venueID: venue?.string("id").flatMap(UUID.init(uuidString:)), venue: venue?.string("name") ?? "Ort folgt", city: venue?.string("address_city"), attendedAt: (row.string("attended_at") ?? row.string("created_at")).flatMap(FlexibleDateParser.date(from:)), genres: genres, works: works)
        }
    }

    func followedProfiles(userID: UUID, token: String) async -> [FollowedProfile] {
        async let persons = try? followedRows(table: "user_favorite_persons", foreignKey: "person_id", relation: "persons", nameKey: "full_name", kind: .person, userID: userID, token: token)
        async let ensembles = try? followedRows(table: "user_favorite_ensembles", foreignKey: "ensemble_id", relation: "ensembles", nameKey: "name", kind: .ensemble, userID: userID, token: token)
        async let venues = try? followedRows(table: "user_favorite_venues", foreignKey: "venue_id", relation: "venues", nameKey: "name", kind: .venue, userID: userID, token: token)
        return await ((persons ?? []) + (ensembles ?? []) + (venues ?? [])).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func followedRows(table: String, foreignKey: String, relation: String, nameKey: String, kind: FollowedProfileKind, userID: UUID, token: String) async throws -> [FollowedProfile] {
        let rows: [JSONObject] = try await client.get(table: table, queryItems: [URLQueryItem(name: "select", value: "\(foreignKey),\(relation)(id,slug,\(nameKey),photo_url)"), URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string(foreignKey).flatMap(UUID.init(uuidString:)), let entity = row.object(relation) else { return nil }
            return FollowedProfile(id: id, kind: kind, name: entity.string(nameKey) ?? "Profil", slug: entity.string("slug"), imageURL: entity.string("photo_url").flatMap(URL.init(string:)))
        }
    }
}

struct VisitedConcertsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var concerts: [VisitedConcert] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView("Besuche laden …") }
            else if concerts.isEmpty { ContentUnavailableView("Noch kein Konzertbesuch", systemImage: "ticket", description: Text("Markiere ein Konzert als besucht, dann wird hier deine Klanghistorie aufgebaut.")) }
            else { List(concerts) { concert in
                VStack(alignment: .leading, spacing: 5) {
                    Text(concert.title).font(.headline)
                    Text([concert.venue, concert.city].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    HStack { if let date = concert.attendedAt { Text(KlangradarDateTime.string(date, format: "d. MMMM yyyy")) }; Spacer(); Text("+\(15 + concert.works.count * 8) XP").foregroundStyle(KlangradarTheme.accent) }.font(.caption.weight(.semibold))
                }.padding(.vertical, 4)
            } }
        }
        .navigationTitle("Besuchte Konzerte")
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        concerts = (try? await repository.visitedConcerts(userID: userID, token: token)) ?? []
    }
}

struct FollowedPeopleView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var followed: [FollowedProfile] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView("Gefolgte Profile laden …") }
            else if followed.isEmpty { ContentUnavailableView("Du folgst noch niemandem", systemImage: "person.badge.plus", description: Text("Folge Personen und Ensembles auf deren Profilseite.")) }
            else { List {
                ForEach(FollowedProfileKind.allVisible, id: \.rawValue) { kind in
                    let entries = followed.filter { $0.kind == kind }
                    if !entries.isEmpty { Section(kind.title) { ForEach(entries) { profile in followedRow(profile) } } }
                }
            } }
        }
        .navigationTitle("Gefolgt")
        .task { await load() }
    }

    private func followedRow(_ profile: FollowedProfile) -> some View {
        NavigationLink(value: EntityRoute(kind: profile.kind.entityKind, identifier: profile.slug ?? profile.id.uuidString)) {
            HStack(spacing: 12) {
                AsyncImage(url: profile.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: profile.kind.entityKind.systemImage).foregroundStyle(KlangradarTheme.accent) }
                    .frame(width: 46, height: 46).clipShape(Circle())
                Text(profile.name).font(.headline)
            }.padding(.vertical, 3)
        }
    }

    private func load() async {
        defer { isLoading = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        followed = await repository.followedProfiles(userID: userID, token: token)
    }
}

struct LevelDetailView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var summary = ProfileSocialSummary.empty

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                levelHeader
                discoveryGrid
                achievementsSection
                landscapeSection
            }.padding(16).padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Klanglevel")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var levelHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.24), lineWidth: 8)
                    Circle().trim(from: 0, to: summary.progressToNext).stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) { Text("\(summary.level)").font(.title.bold()); Text("LEVEL").font(.caption2.bold()).tracking(1) }
                }.frame(width: 94, height: 94)
                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.levelStage.title).font(.title.bold())
                    Text("\(summary.xp.formatted()) Klangpunkte").font(.headline)
                    if summary.levelStage.nextXP != nil { Text("Noch \(summary.xpToNext) XP bis zum nächsten Level").font(.caption).foregroundStyle(.white.opacity(0.78)) }
                }
            }
            Text("Echte musikalische Entdeckung zählt: Besuche, neue Werke, Komponist:innen und Spielstätten.").font(.subheadline).foregroundStyle(.white.opacity(0.86))
        }.foregroundStyle(.white).padding(20).background(LinearGradient(colors: [KlangradarTheme.accent, .indigo.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 26, style: .continuous))
    }

    private var discoveryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meine Klangreise").font(.title2.bold())
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                journeyValue(summary.visitedConcerts, "Konzerte", "ticket.fill")
                journeyValue(summary.uniqueWorks.count, "Werke", "music.note.list")
                journeyValue(summary.uniqueComposers.count, "Komponist:innen", "person.wave.2.fill")
                journeyValue(summary.uniqueVenues.count, "Spielstätten", "building.columns.fill")
                journeyValue(summary.uniqueCities.count, "Städte", "map.fill")
                journeyValue(summary.savedEvents, "Gespeichert", "heart.fill")
            }
        }
    }

    private func journeyValue(_ value: Int, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(KlangradarTheme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) { Text("\(value)").font(.title3.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }.padding(13).background(.background, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements").font(.title2.bold())
            ForEach(summary.achievements) { achievement in
                HStack(spacing: 12) {
                    Image(systemName: achievement.symbol).font(.title3).foregroundStyle(achievement.isUnlocked ? KlangradarTheme.accent : .secondary).frame(width: 42, height: 42).background((achievement.isUnlocked ? KlangradarTheme.accent : Color.secondary).opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 3) { Text(achievement.title).font(.headline); Text(achievement.detail).font(.caption).foregroundStyle(.secondary); ProgressView(value: min(1, Double(achievement.progress) / Double(achievement.target))).tint(KlangradarTheme.accent) }
                    Text("\(min(achievement.progress, achievement.target))/\(achievement.target)").font(.caption.bold()).monospacedDigit().foregroundStyle(.secondary)
                }.padding(13).background(.background, in: .rect(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var landscapeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meine Musiklandschaft").font(.title2.bold())
            if summary.genreCounts.isEmpty {
                Text("Mit jedem besuchten Konzert entsteht hier dein persönliches Entdeckungsprofil.").font(.subheadline).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: .rect(cornerRadius: 18))
            } else {
                let maximum = max(1, summary.genreCounts.first?.1 ?? 1)
                VStack(spacing: 13) {
                    ForEach(Array(summary.genreCounts.prefix(6)), id: \.0) { genre, count in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(genre).font(.subheadline.weight(.semibold)); Spacer(); Text("\(Int(Double(count) / Double(maximum) * 100)) %").font(.caption.bold()).foregroundStyle(.secondary) }
                            ProgressView(value: Double(count), total: Double(maximum)).tint(KlangradarTheme.accent)
                        }
                    }
                }.padding(16).background(.background, in: .rect(cornerRadius: 18))
            }
        }
    }

    private func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        summary = await repository.socialProfileSummary(userID: userID, token: token)
    }
}
