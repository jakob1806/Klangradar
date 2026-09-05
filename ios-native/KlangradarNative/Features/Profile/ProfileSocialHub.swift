import SwiftUI

private struct VenueLocationDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let city: String?
    let lat: Double
    let lng: Double
}

struct ArchivedConcert: Identifiable, Sendable {
    let event: ConcertEvent
    let city: String?
    let searchableText: String
    var id: UUID { event.id }
}

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
    let event: ConcertEvent?
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
    var followedPeople: Int { followed.count }
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
        let symphonicVisits = visits.filter { $0.genres.contains(where: { $0.localizedCaseInsensitiveContains("ymph") || $0.localizedCaseInsensitiveContains("Orchester") }) }.count
        let chamberVisits = visits.filter { $0.genres.contains(where: { $0.localizedCaseInsensitiveContains("Kammer") }) }.count
        let baroqueVisits = visits.filter { $0.genres.contains(where: { $0.localizedCaseInsensitiveContains("Barock") || $0.localizedCaseInsensitiveContains("Alte Musik") }) }.count
        let vocalVisits = visits.filter { $0.genres.contains(where: { $0.localizedCaseInsensitiveContains("Vokal") || $0.localizedCaseInsensitiveContains("Lied") || $0.localizedCaseInsensitiveContains("Chor") }) }.count
        let recentYearVisits = visits.filter { Calendar.current.component(.year, from: $0.attendedAt ?? .distantPast) == Calendar.current.component(.year, from: .now) }.count
        return [
            .init(id: "first", title: "Erster Vorhang", detail: "Das erste Konzert dokumentieren", symbol: "sparkles", progress: visitedConcerts, target: 1),
            .init(id: "season", title: "Saisonklang", detail: "12 Konzerte in einem Kalenderjahr", symbol: "calendar", progress: recentYearVisits, target: 12),
            .init(id: "mahler", title: "Mahler-Marathon", detail: "5 verschiedene Mahler-Werke live", symbol: "waveform.path", progress: mahler, target: 5),
            .init(id: "opera", title: "Opernentdecker", detail: "5 verschiedene Opernhäuser", symbol: "theatermasks.fill", progress: operaVenues, target: 5),
            .init(id: "new", title: "Neue Klänge", detail: "10 Werke nach 2000", symbol: "sparkles", progress: newMusic, target: 10),
            .init(id: "mozart", title: "Mozart-Kenner", detail: "15 verschiedene Mozart-Werke", symbol: "music.quarternote.3", progress: mozart, target: 15),
            .init(id: "munich", title: "München komplett", detail: "10 Münchner Spielstätten", symbol: "building.columns.fill", progress: munichVenues, target: 10),
            .init(id: "cities", title: "Weltenbummler", detail: "Konzerte in 5 Städten", symbol: "globe.europe.africa.fill", progress: uniqueCities.count, target: 5),
            .init(id: "premiere", title: "Premierenjäger", detail: "3 Premieren oder Uraufführungen", symbol: "star.fill", progress: premieres, target: 3),
            .init(id: "symphonic", title: "Große Besetzung", detail: "10 sinfonische Konzerte", symbol: "person.3.fill", progress: symphonicVisits, target: 10),
            .init(id: "chamber", title: "Nah am Klang", detail: "8 Kammermusikabende", symbol: "music.note.house.fill", progress: chamberVisits, target: 8),
            .init(id: "baroque", title: "Zeitreisender", detail: "6 Barock- oder Alte-Musik-Konzerte", symbol: "scroll.fill", progress: baroqueVisits, target: 6),
            .init(id: "vocal", title: "Stimmenkenner", detail: "8 Lied-, Chor- oder Vokalabende", symbol: "music.mic", progress: vocalVisits, target: 8),
            .init(id: "works", title: "Partiturleser", detail: "25 verschiedene Werke live", symbol: "music.note.list", progress: uniqueWorks.count, target: 25),
            .init(id: "venues", title: "Saalwanderer", detail: "15 verschiedene Spielstätten", symbol: "map.fill", progress: uniqueVenues.count, target: 15),
            .init(id: "composers", title: "Kanonbrecher", detail: "20 verschiedene Komponist:innen", symbol: "person.2.wave.2.fill", progress: uniqueComposers.count, target: 20)
        ]
    }
}

extension UserRepository {
    func archivedEvents(limit: Int = 500) async throws -> [ArchivedConcert] {
        let rows: [JSONObject] = try await client.get(table: "events", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,title,subtitle,start_datetime,image_urls,status,category,is_free,venues(id,name,address_city,photo_url),event_genres(genres(id,slug,label_de)),event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url)),event_works(works(title,composer:persons(full_name)))"),
            URLQueryItem(name: "start_datetime", value: "lt.\(ISO8601DateFormatter().string(from: .now))"),
            URLQueryItem(name: "order", value: "start_datetime.desc"),
            URLQueryItem(name: "limit", value: String(limit))
        ])
        return rows.compactMap { row in
            guard let event = ConcertEvent(json: row) else { return nil }
            let city = row.object("venues")?.string("address_city")
            let workTerms = row.objects("event_works").flatMap { relation -> [String] in
                guard let work = relation.object("works") else { return [] }
                return [work.string("title"), work.object("composer")?.string("full_name")].compactMap { $0 }
            }
            let participantTerms = row.objects("event_participants").flatMap { relation in
                [relation.object("persons")?.string("full_name"), relation.object("ensembles")?.string("name")].compactMap { $0 }
            }
            let terms = [event.title, event.subtitle, event.venues?.name, city, event.category].compactMap { $0 } + event.genreLabels + participantTerms + workTerms
            return ArchivedConcert(event: event, city: city, searchableText: terms.joined(separator: " "))
        }
    }

    func hasAttended(eventID: UUID, userID: UUID, token: String) async throws -> Bool {
        let rows: [JSONObject] = try await client.get(table: "event_attendance", queryItems: [
            URLQueryItem(name: "select", value: "event_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)"),
            URLQueryItem(name: "status", value: "eq.attended"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: token)
        return !rows.isEmpty
    }

    /// Für AttendanceLocationMonitor: gemerkte, bevorstehende Events mit
    /// bekannter Spielstätte, als Kandidaten für die passive, standort-
    /// basierte Besuchs-Erkennung im Hintergrund (siehe dort). Filtert
    /// client-seitig statt über einen PostgREST-Embed-Filter, da ein Filter
    /// auf `events.start_datetime` ohne `!inner`-Join nicht ausschließt,
    /// sondern nur `events: null` liefert.
    func upcomingFavoritesWithVenue(userID: UUID, token: String, within: TimeInterval = 24 * 3600) async throws -> [AttendanceCandidate] {
        let rows: [JSONObject] = try await client.get(table: "favorites", queryItems: [
            URLQueryItem(name: "select", value: "events(id,title,start_datetime,venues(id))"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ], accessToken: token)
        let now = Date()
        return rows.compactMap { row -> AttendanceCandidate? in
            guard let event = row.object("events"),
                  let idString = event.string("id"), let id = UUID(uuidString: idString),
                  let title = event.string("title"),
                  let startString = event.string("start_datetime"), let start = FlexibleDateParser.date(from: startString),
                  let venue = event.object("venues"), let venueIDString = venue.string("id"), let venueID = UUID(uuidString: venueIDString)
            else { return nil }
            guard start >= now.addingTimeInterval(-2 * 3600), start <= now.addingTimeInterval(within) else { return nil }
            return AttendanceCandidate(eventID: id, title: title, startDate: start, venueID: venueID)
        }
    }

    func venueLocation(id: UUID) async throws -> VenueLocation? {
        let rows: [VenueLocationDTO] = try await client.rpc("venues_with_latlng")
        return rows.first(where: { $0.id == id }).map {
            VenueLocation(id: $0.id, name: $0.name, city: $0.city, latitude: $0.lat, longitude: $0.lng)
        }
    }

    func setAttended(eventID: UUID, attended: Bool, attendedAt: Date?, verificationType: String = "manual", userID: UUID, token: String) async throws {
        if attended {
            var values: JSONObject = [
                "user_id": .string(userID.uuidString),
                "event_id": .string(eventID.uuidString),
                "status": .string("attended"),
                "verification_type": .string(verificationType),
                "updated_at": .string(ISO8601DateFormatter().string(from: .now))
            ]
            values["attended_at"] = .string(ISO8601DateFormatter().string(from: attendedAt ?? .now))
            try await client.upsert(table: "event_attendance", values: values, accessToken: token, conflictColumns: "user_id,event_id")
        } else {
            try await client.delete(table: "event_attendance", filters: [
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
                URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)")
            ], accessToken: token)
        }
    }

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
        let selection = "event_id,attended_at,created_at,events(id,slug,title,subtitle,start_datetime,image_urls,status,category,is_free,venues(id,name,address_city,photo_url),event_genres(genres(id,slug,label_de)),event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url)),event_works(works(id,title,composition_year,composer:persons(id,full_name))))"
        let rows: [JSONObject] = try await client.get(table: "event_attendance", queryItems: [
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
            return VisitedConcert(id: id, title: event.string("title") ?? "Konzert", venueID: venue?.string("id").flatMap(UUID.init(uuidString:)), venue: venue?.string("name") ?? "Ort folgt", city: venue?.string("address_city"), attendedAt: (row.string("attended_at") ?? row.string("created_at")).flatMap(FlexibleDateParser.date(from:)), genres: genres, works: works, event: ConcertEvent(json: event))
        }
    }

    /// Für die "Geplant"-Kachel unter "Mein Klangradar" (my_klangradar_stats
    /// zählt dasselbe: favorites mit status='attending' und zukünftigem
    /// Beginn) -- dieselbe Event-Selektion wie visitedConcerts/eventLists,
    /// damit Navigation zur Detailseite identisch funktioniert.
    func plannedEvents(userID: UUID, token: String) async throws -> [ConcertEvent] {
        let selection = "events(id,slug,title,subtitle,start_datetime,image_urls,status,category,is_free,venues(id,name,photo_url),event_genres(genres(id,slug,label_de)))"
        let rows: [JSONObject] = try await client.get(table: "favorites", queryItems: [
            URLQueryItem(name: "select", value: selection),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "status", value: "eq.attending"),
        ], accessToken: token)
        let now = Date()
        return rows.compactMap { row -> ConcertEvent? in
            guard let event = row.object("events"), let concert = ConcertEvent(json: event), let start = concert.startDate, start >= now else { return nil }
            return concert
        }.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    /// Für die "Werke"-Kachel unter "Mein Klangradar" -- dieselben Felder
    /// wie VisitedWork (VisitedConcert.works), damit eine Zeile identisch
    /// aussieht, egal ob das Werk aus einem Besuch oder direkt gefolgt wurde.
    func followedWorks(userID: UUID, token: String) async throws -> [VisitedWork] {
        let rows: [JSONObject] = try await client.get(table: "user_favorite_works", queryItems: [
            URLQueryItem(name: "select", value: "works(id,title,composition_year,composer:persons(id,full_name))"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
        ], accessToken: token)
        return rows.compactMap { row -> VisitedWork? in
            guard let work = row.object("works"), let idString = work.string("id"), let id = UUID(uuidString: idString), let title = work.string("title") else { return nil }
            let composer = work.object("composer")
            return VisitedWork(id: id, title: title, composerID: composer?.string("id").flatMap(UUID.init(uuidString:)), composerName: composer?.string("full_name"), compositionYear: work.integer("composition_year"))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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

struct ConcertArchiveView: View {
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var events: [ArchivedConcert] = []
    @State private var query = ""
    @State private var selectedYear: Int?
    @State private var selectedCity: String?
    @State private var isLoading = true

    private var years: [Int] {
        Array(Set(events.compactMap { $0.event.startDate.map { Calendar.current.component(.year, from: $0) } })).sorted(by: >)
    }

    private var cities: [String] { Array(Set(events.compactMap(\.city))).sorted() }

    private var filteredEvents: [ArchivedConcert] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter { archived in
            let matchesYear = selectedYear == nil || archived.event.startDate.map { Calendar.current.component(.year, from: $0) == selectedYear } == true
            let matchesCity = selectedCity == nil || archived.city == selectedCity
            guard matchesYear, matchesCity, !term.isEmpty else { return matchesYear && matchesCity }
            return archived.searchableText.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        Group {
            if isLoading { ProgressView("Konzertarchiv laden …") }
            else if filteredEvents.isEmpty { ContentUnavailableView.search(text: query) }
            else {
                List(filteredEvents) { archived in
                    NavigationLink {
                        EventDetailView(event: archived.event, repository: eventRepository, contentRepository: contentRepository)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(archived.event.title).font(.headline).lineLimit(2)
                            Text([archived.event.startDate.map { KlangradarDateTime.string($0, format: "d. MMMM yyyy") }, archived.event.venues?.name].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Konzertarchiv")
        .searchable(text: $query, prompt: "Konzert, Person, Ensemble, Ort, Genre")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Alle Jahre") { selectedYear = nil }
                    ForEach(years, id: \.self) { year in Button(String(year)) { selectedYear = year } }
                } label: { Label(selectedYear.map(String.init) ?? "Jahr", systemImage: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Alle Städte") { selectedCity = nil }
                    ForEach(cities, id: \.self) { city in Button(city) { selectedCity = city } }
                } label: { Text(selectedCity ?? "Stadt") }
            }
        }
        .task {
            events = (try? await repository?.archivedEvents()) ?? []
            isLoading = false
        }
    }
}

struct VisitedConcertsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var concerts: [VisitedConcert] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView("Besuche laden …") }
            else if concerts.isEmpty { ContentUnavailableView("Noch kein Konzertbesuch", systemImage: "ticket", description: Text("Markiere ein Konzert als besucht, dann wird hier deine Klanghistorie aufgebaut.")) }
            else { List(concerts) { concert in
                if let event = concert.event {
                    NavigationLink {
                        EventDetailView(event: event, repository: eventRepository, contentRepository: contentRepository)
                    } label: { concertRow(concert) }
                } else { concertRow(concert) }
            } }
        }
        .navigationTitle("Besuchte Konzerte")
        .task { await load() }
        .refreshable { await load() }
    }

    // Nutzerwunsch: Miniaturbild pro Zeile, konsistent mit dem übrigen
    // App-Design (siehe CalendarEventRow) statt reinem Text.
    private func concertRow(_ concert: VisitedConcert) -> some View {
        HStack(spacing: 12) {
            if let event = concert.event {
                EventArtwork(event: event).frame(width: 52, height: 52).clipped().clipShape(.rect(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemFill)).frame(width: 52, height: 52)
                    .overlay { Image(systemName: "ticket.fill").foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(concert.title).font(.headline)
                Text([concert.venue, concert.city].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                HStack { if let date = concert.attendedAt { Text(KlangradarDateTime.string(date, format: "d. MMMM yyyy")) }; Spacer(); Text("+\(15 + concert.works.count * 8) XP").foregroundStyle(KlangradarTheme.accent) }.font(.caption.weight(.semibold))
            }
        }.padding(.vertical, 4)
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
    let contentRepository: any ContentRepository
    // Nutzerwunsch: "Mein Klangradar"-Kacheln (Personen/Ensembles/Orte)
    // sollen jeweils DIREKT zur passenden Kategorie führen, statt immer zur
    // vollständigen, nach allen drei Arten gruppierten Liste -- optionaler
    // Filter, Standardverhalten (nil) bleibt unverändert (z.B. "Gefolgt"
    // im Hauptprofil).
    var filterKind: FollowedProfileKind?
    @State private var followed: [FollowedProfile] = []
    @State private var isLoading = true

    private var visibleKinds: [FollowedProfileKind] {
        filterKind.map { [$0] } ?? FollowedProfileKind.allVisible
    }

    var body: some View {
        Group {
            if isLoading { ProgressView("Gefolgte Profile laden …") }
            else if followed.filter({ visibleKinds.contains($0.kind) }).isEmpty {
                ContentUnavailableView("Du folgst noch niemandem", systemImage: "person.badge.plus", description: Text("Folge Personen und Ensembles auf deren Profilseite."))
            }
            else { List {
                ForEach(visibleKinds, id: \.rawValue) { kind in
                    let entries = followed.filter { $0.kind == kind }
                    if !entries.isEmpty { Section(filterKind == nil ? kind.title : "") { ForEach(entries) { profile in followedRow(profile) } } }
                }
            } }
        }
        .navigationTitle(filterKind?.title ?? "Gefolgt")
        .task { await load() }
        .refreshable { await load() }
    }

    private func followedRow(_ profile: FollowedProfile) -> some View {
        NavigationLink {
            EntityDetailView(
                route: EntityRoute(kind: profile.kind.entityKind, identifier: profile.slug ?? profile.id.uuidString),
                repository: contentRepository
            )
        } label: {
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
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
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

    // Nutzerwunsch: die Kacheln unter "Meine Klangreise" sollen antippbar
    // sein und zu einer Liste aller zugrundeliegenden Einträge führen
    // (Konzerte, Werke, Komponist:innen, Spielstätten, Städte, Gespeichert)
    // -- vorher waren das reine Zahlen ohne Detailansicht.
    private var discoveryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meine Klangreise").font(.title2.bold())
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                NavigationLink {
                    VisitedConcertsView(auth: auth, repository: repository, eventRepository: eventRepository, contentRepository: contentRepository)
                } label: { journeyValue(summary.visitedConcerts, "Konzerte", "ticket.fill") }
                NavigationLink {
                    VisitedWorksListView(visits: summary.visits, contentRepository: contentRepository)
                } label: { journeyValue(summary.uniqueWorks.count, "Werke", "music.note.list") }
                NavigationLink {
                    VisitedEntityListView(kind: .person, title: "Komponist:innen", entries: composerEntries, contentRepository: contentRepository)
                } label: { journeyValue(summary.uniqueComposers.count, "Komponist:innen", "person.wave.2.fill") }
                NavigationLink {
                    VisitedEntityListView(kind: .venue, title: "Spielstätten", entries: venueEntries, contentRepository: contentRepository)
                } label: { journeyValue(summary.uniqueVenues.count, "Spielstätten", "building.columns.fill") }
                NavigationLink {
                    VisitedCitiesListView(cities: summary.uniqueCities)
                } label: { journeyValue(summary.uniqueCities.count, "Städte", "map.fill") }
                NavigationLink {
                    FavoriteEventsView(auth: auth, repository: repository, eventRepository: eventRepository, contentRepository: contentRepository)
                } label: { journeyValue(summary.savedEvents, "Gespeichert", "heart.fill") }
            }
        }
        .buttonStyle(.plain)
    }

    private var composerEntries: [VisitedEntityEntry] {
        var seen = Set<UUID>()
        return summary.visits.flatMap(\.works).compactMap { work -> VisitedEntityEntry? in
            guard let id = work.composerID, let name = work.composerName, seen.insert(id).inserted else { return nil }
            return VisitedEntityEntry(id: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var venueEntries: [VisitedEntityEntry] {
        var seen = Set<UUID>()
        return summary.visits.compactMap { visit -> VisitedEntityEntry? in
            guard let id = visit.venueID, seen.insert(id).inserted else { return nil }
            return VisitedEntityEntry(id: id, name: visit.venue)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func journeyValue(_ value: Int, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(KlangradarTheme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) { Text("\(value)").font(.title3.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
        }.padding(13).background(.background, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements").font(.title2.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3), spacing: 20) {
                ForEach(summary.achievements) { achievement in
                    achievementTile(achievement)
                }
            }
        }
    }

    private func achievementTile(_ achievement: KlangAchievement) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? KlangradarTheme.accent.opacity(0.14) : Color.secondary.opacity(0.07))
                Circle()
                    .stroke(achievement.isUnlocked ? KlangradarTheme.accent.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: 1)
                    .padding(4)
                Image(systemName: achievement.isUnlocked ? achievement.symbol : "lock.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(achievement.isUnlocked ? KlangradarTheme.accent : Color.secondary.opacity(0.55))
            }
            .frame(width: 72, height: 72)

            Text(achievement.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .top)
            Text(achievement.isUnlocked ? "Erreicht" : "\(min(achievement.progress, achievement.target)) von \(achievement.target)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(achievement.isUnlocked ? KlangradarTheme.accent : .secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title), \(achievement.detail), \(min(achievement.progress, achievement.target)) von \(achievement.target)")
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

/// Nutzerwunsch: "Werke" aus "Meine Klangreise" antippbar machen und dort
/// eine Liste zeigen -- Werke haben in Klangradar kein eigenes Bild, daher
/// ein einheitliches Noten-Icon statt eines Miniaturbilds (konsistent mit
/// den Icon-Kacheln in coachLens/achievementTile).
struct VisitedWorksListView: View {
    let visits: [VisitedConcert]
    let contentRepository: any ContentRepository

    private var works: [VisitedWork] {
        var seen = Set<UUID>()
        return visits.flatMap(\.works).filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        WorkListRows(works: works, contentRepository: contentRepository)
            .overlay { if works.isEmpty { ContentUnavailableView("Noch keine Werke", systemImage: "music.note.list", description: Text("Werke aus besuchten Konzerten erscheinen hier.")) } }
            .navigationTitle("Werke")
    }
}

/// Für die "Werke"-Kachel unter "Mein Klangradar" (direkt gefolgte Werke,
/// nicht nur aus besuchten Konzerten) -- lädt selbst über
/// UserRepository.followedWorks, teilt sich die Zeilendarstellung mit
/// VisitedWorksListView über WorkListRows.
struct FollowedWorksListView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let contentRepository: any ContentRepository
    @State private var works: [VisitedWork] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView("Werke laden …") }
            else { WorkListRows(works: works, contentRepository: contentRepository) }
        }
        .overlay { if !isLoading && works.isEmpty { ContentUnavailableView("Noch keine Werke", systemImage: "music.note.list", description: Text("Gefolgte Werke erscheinen hier.")) } }
        .navigationTitle("Werke")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        works = (try? await repository.followedWorks(userID: userID, token: token)) ?? []
    }
}

/// Gemeinsame Zeilendarstellung für Werke -- jede Zeile führt zur echten
/// Werk-Detailseite (EntityDetailView), damit man von jeder "Mein
/// Klangradar"/"Klangreise"-Liste aus weiternavigieren kann.
private struct WorkListRows: View {
    let works: [VisitedWork]
    let contentRepository: any ContentRepository

    var body: some View {
        List(works, id: \.id) { work in
            NavigationLink {
                EntityDetailView(route: EntityRoute(kind: .work, identifier: work.id.uuidString), repository: contentRepository)
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(KlangradarTheme.accent.opacity(0.14)).frame(width: 44, height: 44)
                        .overlay { Image(systemName: "music.note.list").foregroundStyle(KlangradarTheme.accent) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(work.title).font(.headline)
                        Text([work.composerName, work.compositionYear.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 3)
            }
        }
    }
}

/// Gemeinsamer Eintragstyp für Komponist:innen- und Spielstätten-Listen
/// (beide sind echte Klangradar-Entitäten mit eigener Detailseite und
/// bekanntem Miniaturbild aus dem Verzeichnis, siehe DirectoryItem).
struct VisitedEntityEntry: Identifiable, Hashable {
    let id: UUID
    let name: String
}

/// Nutzerwunsch: "Komponist:innen" und "Spielstätten" antippbar machen und
/// dort eine Liste MIT Miniaturbildern zeigen, konsistent mit dem übrigen
/// Verzeichnis-Design (siehe FollowedPeopleView.followedRow). Löst die
/// Bilder über das ohnehin geladene Verzeichnis auf (directory(kind:))
/// statt pro Eintrag einzeln nachzuladen.
struct VisitedEntityListView: View {
    let kind: EntityKind
    let title: String
    let entries: [VisitedEntityEntry]
    let contentRepository: any ContentRepository
    @State private var images: [UUID: URL] = [:]

    var body: some View {
        List(entries) { entry in
            NavigationLink {
                EntityDetailView(route: EntityRoute(kind: kind, identifier: entry.id.uuidString), repository: contentRepository)
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: images[entry.id]) { image in image.resizable().scaledToFill() } placeholder: {
                        Image(systemName: kind.systemImage).foregroundStyle(KlangradarTheme.accent)
                    }
                    .frame(width: 46, height: 46)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(kind == .venue ? AnyShape(RoundedRectangle(cornerRadius: 10)) : AnyShape(Circle()))
                    Text(entry.name).font(.headline)
                }.padding(.vertical, 3)
            }
        }
        .overlay { if entries.isEmpty { ContentUnavailableView("Noch keine Einträge", systemImage: kind.systemImage, description: Text("Einträge aus besuchten Konzerten erscheinen hier.")) } }
        .navigationTitle(title)
        .task {
            guard images.isEmpty, let items = try? await contentRepository.directory(kind: kind) else { return }
            let byID = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (UUID, URL)? in
                guard let id = UUID(uuidString: item.id), let url = item.imageURL else { return nil }
                return (id, url)
            })
            images = byID
        }
    }
}

/// Nutzerwunsch: "Städte" antippbar machen -- Städte sind keine eigene
/// Klangradar-Entität mit Detailseite, daher eine einfache Liste ohne
/// Navigation, mit demselben Icon-Avatar-Stil wie VisitedWorksListView.
struct VisitedCitiesListView: View {
    let cities: Set<String>

    private var sorted: [String] { cities.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    var body: some View {
        List(sorted, id: \.self) { city in
            HStack(spacing: 12) {
                Circle().fill(KlangradarTheme.accent.opacity(0.14)).frame(width: 44, height: 44)
                    .overlay { Image(systemName: "map.fill").foregroundStyle(KlangradarTheme.accent) }
                Text(city).font(.headline)
            }.padding(.vertical, 3)
        }
        .overlay { if sorted.isEmpty { ContentUnavailableView("Noch keine Städte", systemImage: "map", description: Text("Städte aus besuchten Konzerten erscheinen hier.")) } }
        .navigationTitle("Städte")
    }
}
