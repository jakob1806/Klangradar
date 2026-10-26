// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): eigene Konzerteinträge
// im Stil von Apple Journal – für Konzerte, die nicht in Klangradar stehen.
import Foundation

struct JournalPick: Identifiable, Hashable, Sendable {
    let kind: EntityKind
    let entityID: UUID?
    let name: String
    var detail: String? = nil
    var photoURL: URL? = nil
    var role: String? = nil
    var id: String { entityID?.uuidString ?? "\(kind.rawValue):\(name)" }
}

struct ConcertJournalEntry: Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var title = ""
    var startsAt = Date()
    var durationMinutes: Int? = nil
    var venue: JournalPick? = nil
    var program: [JournalPick] = []
    var participants: [JournalPick] = []
    var note = ""
    var photoPaths: [String] = []

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

@MainActor
enum JournalAPI {
    private static var client: SupabaseRESTClient? { SocialStore.shared.repository?.client }
    private static var token: String? { SocialStore.shared.token }

    /// Suche in den Stammdaten je Typ (Werke auch über "Komponist Titel").
    static func search(_ kind: EntityKind, _ query: String) async -> [JournalPick] {
        guard let client else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let pattern = "*\(q.replacingOccurrences(of: "*", with: ""))*"
        switch kind {
        case .person:
            let rows: [JSONObject] = (try? await client.get(table: "persons", queryItems: [
                URLQueryItem(name: "select", value: "id,full_name,photo_url,instrument"),
                URLQueryItem(name: "full_name", value: "ilike.\(pattern)"),
                URLQueryItem(name: "limit", value: "20")
            ])) ?? []
            return rows.compactMap { row in
                guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let name = row.string("full_name") else { return nil }
                return JournalPick(kind: .person, entityID: id, name: name, detail: row.string("instrument"), photoURL: row.string("photo_url").flatMap(URL.init(string:)))
            }
        case .ensemble:
            let rows: [JSONObject] = (try? await client.get(table: "ensembles", queryItems: [
                URLQueryItem(name: "select", value: "id,name,photo_url"),
                URLQueryItem(name: "name", value: "ilike.\(pattern)"),
                URLQueryItem(name: "is_resolution_placeholder", value: "eq.false"),
                URLQueryItem(name: "limit", value: "20")
            ])) ?? []
            return rows.compactMap { row in
                guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let name = row.string("name") else { return nil }
                return JournalPick(kind: .ensemble, entityID: id, name: name, photoURL: row.string("photo_url").flatMap(URL.init(string:)))
            }
        case .venue:
            let rows: [JSONObject] = (try? await client.get(table: "venues", queryItems: [
                URLQueryItem(name: "select", value: "id,name,address_city,photo_url"),
                URLQueryItem(name: "name", value: "ilike.\(pattern)"),
                URLQueryItem(name: "limit", value: "20")
            ])) ?? []
            return rows.compactMap { row in
                guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let name = row.string("name") else { return nil }
                return JournalPick(kind: .venue, entityID: id, name: name, detail: row.string("address_city"), photoURL: row.string("photo_url").flatMap(URL.init(string:)))
            }
        case .work:
            async let byTitle: [JSONObject] = (try? await client.get(table: "works", queryItems: [
                URLQueryItem(name: "select", value: "id,title,catalog_number,composer:persons(full_name)"),
                URLQueryItem(name: "title", value: "ilike.\(pattern)"),
                URLQueryItem(name: "limit", value: "20")
            ])) ?? []
            // "Beethoven 7" → Werke des Komponisten, deren Titel den Rest enthält.
            let tokens = q.split(separator: " ").map(String.init)
            async let byComposer: [JSONObject] = {
                guard let first = tokens.first, first.count >= 3 else { return [] }
                var items = [
                    URLQueryItem(name: "select", value: "id,title,catalog_number,composer:persons!inner(full_name)"),
                    URLQueryItem(name: "composer.full_name", value: "ilike.*\(first)*"),
                    URLQueryItem(name: "limit", value: "30")
                ]
                for token in tokens.dropFirst() { items.append(URLQueryItem(name: "title", value: "ilike.*\(token)*")) }
                return (try? await client.get(table: "works", queryItems: items)) ?? []
            }()
            var seen = Set<String>()
            return (await byComposer + byTitle).compactMap { row in
                guard let raw = row.string("id"), seen.insert(raw).inserted, let id = UUID(uuidString: raw), let title = row.string("title") else { return nil }
                let detail = [row.object("composer")?.string("full_name"), row.string("catalog_number")].compactMap { $0 }.joined(separator: " · ")
                return JournalPick(kind: .work, entityID: id, name: title, detail: detail.isEmpty ? nil : detail)
            }
        }
    }

    /// Fehlenden Eintrag mit Namen anfragen – wird sofort angelegt (bzw. gefunden)
    /// und automatisch angereichert; die Redaktion bekommt die Anfrage.
    static func request(_ kind: EntityKind, name: String, context: String?) async throws -> JournalPick {
        guard let client, let token else { throw URLError(.userAuthenticationRequired) }
        var body: JSONObject = ["type": .string(kind.rawValue), "name": .string(name)]
        if let context, !context.isEmpty { body["context"] = .string(context) }
        let response: JSONObject = try await client.edgeFunction("request-entity", body: body, accessToken: token)
        return JournalPick(kind: kind, entityID: response.string("id").flatMap(UUID.init(uuidString:)), name: name,
                           detail: response.string("status") == "needs_review" ? "Wird von der Redaktion ergänzt" : context)
    }

    static func entries() async -> [ConcertJournalEntry] {
        guard let client, let token, let userID = PlannerAPI.userID else { return [] }
        let rows: [JSONObject] = (try? await client.get(table: "user_concert_entries", queryItems: [
            URLQueryItem(name: "select", value: "*,venues(id,name,address_city)"),
            URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)"),
            URLQueryItem(name: "order", value: "starts_at.desc")
        ], accessToken: token)) ?? []
        return rows.compactMap(Self.entry)
    }

    private static func entry(_ row: JSONObject) -> ConcertJournalEntry? {
        guard let id = row.string("id").flatMap(UUID.init(uuidString:)) else { return nil }
        var entry = ConcertJournalEntry(id: id)
        entry.title = row.string("title") ?? ""
        entry.startsAt = row.string("starts_at").flatMap(Self.parseDate) ?? .now
        entry.durationMinutes = row.integer("duration_minutes")
        if let venue = row.object("venues"), let name = venue.string("name") {
            entry.venue = JournalPick(kind: .venue, entityID: venue.string("id").flatMap(UUID.init(uuidString:)), name: name, detail: venue.string("address_city"))
        } else if let name = row.string("venue_name") {
            entry.venue = JournalPick(kind: .venue, entityID: nil, name: name)
        }
        entry.program = row.objects("program").compactMap { item in
            item.string("title").map { JournalPick(kind: .work, entityID: item.string("work_id").flatMap(UUID.init(uuidString:)), name: $0, detail: item.string("composer")) }
        }
        entry.participants = row.objects("participants").compactMap { item in
            guard let name = item.string("name") else { return nil }
            return JournalPick(kind: item.string("kind") == "ensemble" ? .ensemble : .person, entityID: item.string("id").flatMap(UUID.init(uuidString:)), name: name, role: item.string("role"))
        }
        entry.note = row.string("note") ?? ""
        entry.photoPaths = row.strings("photo_paths")
        return entry
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func save(_ entry: ConcertJournalEntry) async throws {
        guard let client, let token, let userID = PlannerAPI.userID else { return }
        func text(_ value: String) -> JSONValue { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .null : .string(value) }
        try await client.upsert(table: "user_concert_entries", values: [
            "id": .string(entry.id.uuidString),
            "user_id": .string(userID.uuidString),
            "title": text(entry.title),
            "starts_at": .string(ISO8601DateFormatter().string(from: entry.startsAt)),
            "duration_minutes": entry.durationMinutes.map { .number(Double($0)) } ?? .null,
            "venue_id": entry.venue?.entityID.map { .string($0.uuidString) } ?? .null,
            "venue_name": entry.venue.map { .string($0.name) } ?? .null,
            "program": .array(entry.program.map { work in
                .object(["work_id": work.entityID.map { .string($0.uuidString) } ?? .null, "title": .string(work.name), "composer": work.detail.map { .string($0) } ?? .null])
            }),
            "participants": .array(entry.participants.map { person in
                .object(["kind": .string(person.kind.rawValue), "id": person.entityID.map { .string($0.uuidString) } ?? .null,
                         "name": .string(person.name), "role": person.role.map { .string($0) } ?? .null])
            }),
            "note": text(entry.note),
            "photo_paths": .array(entry.photoPaths.map { .string($0) }),
            "updated_at": .string(ISO8601DateFormatter().string(from: .now))
        ], accessToken: token, conflictColumns: "id")
    }

    static func delete(_ id: UUID) async {
        guard let client, let token else { return }
        try? await client.delete(table: "user_concert_entries", filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")], accessToken: token)
    }

    static func uploadPhoto(_ data: Data, entryID: UUID) async throws -> String? {
        guard let client, let token, let userID = PlannerAPI.userID else { return nil }
        let path = "\(userID.uuidString.lowercased())/journal/\(entryID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.uploadPublicObject(bucket: "diary-photos", path: path, data: data, contentType: "image/jpeg", accessToken: token)
        return path
    }
}
