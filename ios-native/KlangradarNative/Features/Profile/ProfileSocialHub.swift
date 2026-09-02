import SwiftUI

struct ProfileSocialSummary: Sendable {
    let visitedConcerts: Int
    let followedPeople: Int

    var level: Int { max(1, min(50, 1 + visitedConcerts / 3 + followedPeople / 12)) }
    var levelTitle: String {
        switch level {
        case 1...3: "Entdecker:in"
        case 4...8: "Konzertgänger:in"
        case 9...16: "Kenner:in"
        default: "Klangradar Insider"
        }
    }
}

struct VisitedConcert: Identifiable, Sendable {
    let id: UUID
    let title: String
    let venue: String
    let attendedAt: Date?
}

struct FollowedPerson: Identifiable, Sendable {
    let id: UUID
    let name: String
    let subtitle: String?
    let imageURL: URL?
}

extension UserRepository {
    /// Alle Abfragen sind bewusst unabhängig: Ein noch nicht migrierter
    /// Besuchsverlauf darf niemals den gesamten Profilbereich blockieren.
    func socialProfileSummary(userID: UUID, token: String) async -> ProfileSocialSummary {
        async let visits = visitedConcerts(userID: userID, token: token)
        async let follows = followedPeople(userID: userID, token: token)
        return await ProfileSocialSummary(visitedConcerts: (try? visits.count) ?? 0, followedPeople: (try? follows.count) ?? 0)
    }

    func visitedConcerts(userID: UUID, token: String) async throws -> [VisitedConcert] {
        let rows: [JSONObject] = try await client.get(table: "coach_event_reflections", queryItems: [
            URLQueryItem(name: "select", value: "event_id,attended_at,created_at,events(title,venues(name))"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "order", value: "attended_at.desc.nullslast,created_at.desc")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("event_id").flatMap(UUID.init(uuidString:)), let event = row.object("events") else { return nil }
            return VisitedConcert(id: id, title: event.string("title") ?? "Konzert", venue: event.object("venues")?.string("name") ?? "Ort folgt", attendedAt: row.string("attended_at").flatMap(FlexibleDateParser.date(from:)))
        }
    }

    func followedPeople(userID: UUID, token: String) async throws -> [FollowedPerson] {
        let rows: [JSONObject] = try await client.get(table: "user_favorite_persons", queryItems: [
            URLQueryItem(name: "select", value: "person_id,persons(full_name,subtitle,photo_url)"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
        ], accessToken: token)
        return rows.compactMap { row in
            guard let id = row.string("person_id").flatMap(UUID.init(uuidString:)), let person = row.object("persons") else { return nil }
            return FollowedPerson(id: id, name: person.string("full_name") ?? "Person", subtitle: person.string("subtitle"), imageURL: person.string("photo_url").flatMap(URL.init(string:)))
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
            else if concerts.isEmpty { ContentUnavailableView("Noch kein Konzertbesuch", systemImage: "ticket", description: Text("Reflektiere einen Konzertabend, dann erscheint er hier.")) }
            else { List(concerts) { concert in
                VStack(alignment: .leading, spacing: 4) {
                    Text(concert.title).font(.headline)
                    Text(concert.venue).foregroundStyle(.secondary)
                    if let date = concert.attendedAt { Text(KlangradarDateTime.string(date, format: "d. MMMM yyyy")).font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 3)
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
    @State private var people: [FollowedPerson] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView("Gefolgte Personen laden …") }
            else if people.isEmpty { ContentUnavailableView("Du folgst noch niemandem", systemImage: "person.badge.plus", description: Text("Folge Künstler:innen, um ihre Konzerte zuerst zu sehen.")) }
            else { List(people) { person in
                HStack(spacing: 12) {
                    AsyncImage(url: person.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").foregroundStyle(KlangradarTheme.accent) }
                        .frame(width: 48, height: 48).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) { Text(person.name).font(.headline); if let subtitle = person.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) } }
                }.padding(.vertical, 3)
            } }
        }
        .navigationTitle("Gefolgt")
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        people = (try? await repository.followedPeople(userID: userID, token: token)) ?? []
    }
}

struct LevelDetailView: View {
    let summary: ProfileSocialSummary
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "medal.fill").font(.system(size: 54)).foregroundStyle(KlangradarTheme.accent)
            Text("Level \(summary.level)").font(.largeTitle.bold())
            Text(summary.levelTitle).font(.title3).foregroundStyle(.secondary)
            Text("Dein Level wächst mit besuchten Konzerten und den Künstler:innen, denen du folgst.").multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Dein Level")
    }
}
