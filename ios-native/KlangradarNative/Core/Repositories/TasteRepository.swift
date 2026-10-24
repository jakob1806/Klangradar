// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 4–7).
import Foundation

struct TasteProfile: Sendable {
    struct Entry: Identifiable, Sendable {
        let id: UUID
        let name: String
        let weight: Double
        var kind: String? = nil
    }
    let composers: [Entry]
    let artists: [Entry]
    let venues: [Entry]
    /// ISO-Wochentag (1 = Mo) → Gewicht
    let weekdays: [Int: Double]
    /// "tag" | "vorabend" | "abend" → Gewicht
    let bands: [String: Double]
    let signalCount: Int

    var isEmpty: Bool { composers.isEmpty && artists.isEmpty && venues.isEmpty }
}

extension UserRepository {
    /// Wandelt sowohl `["…"]` als auch `[{"fn": "…"}]` in UUIDs.
    private func uuids(_ value: JSONValue) -> [UUID] {
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item in
            switch item {
            case let .string(raw): return UUID(uuidString: raw)
            case let .object(row): return row.values.compactMap { if case let .string(raw) = $0 { UUID(uuidString: raw) } else { nil } }.first
            default: return nil
            }
        }
    }

    func tasteReasons(eventIDs: [UUID], token: String) async throws -> [UUID: (reason: String?, boost: Double)] {
        guard !eventIDs.isEmpty else { return [:] }
        let rows: [JSONObject] = try await client.rpc(
            "taste_reasons",
            parameters: ["p_event_ids": .array(eventIDs.map { .string($0.uuidString) })],
            accessToken: token
        )
        var result: [UUID: (String?, Double)] = [:]
        for row in rows {
            guard let id = row.string("event_id").flatMap(UUID.init(uuidString:)) else { continue }
            result[id] = (row.string("reason"), row.number("boost") ?? 0)
        }
        return result
    }

    func discoverOutsideTaste(cityID: UUID?, limit: Int = 8, token: String?) async throws -> [UUID] {
        let value: JSONValue = try await client.rpc(
            "discover_outside_taste",
            parameters: ["p_city_id": cityID.map { .string($0.uuidString) } ?? .null, "p_limit": .number(Double(limit))],
            accessToken: token
        )
        return uuids(value)
    }

    func pendingRatings(token: String) async throws -> [UUID] {
        let value: JSONValue = try await client.rpc("pending_ratings", accessToken: token)
        return uuids(value)
    }

    func tasteProfile(token: String) async throws -> TasteProfile {
        let row: JSONObject = try await client.rpc("my_taste_profile", accessToken: token)
        func entries(_ key: String) -> [TasteProfile.Entry] {
            row.objects(key).compactMap { item in
                guard let id = item.string("id").flatMap(UUID.init(uuidString:)), let name = item.string("name") else { return nil }
                return TasteProfile.Entry(id: id, name: name, weight: item.number("weight") ?? 0, kind: item.string("kind"))
            }
        }
        func map(_ key: String) -> [String: Double] {
            guard case let .object(values)? = row[key] else { return [:] }
            return values.compactMapValues { if case let .number(n) = $0 { n } else { nil } }
        }
        return TasteProfile(
            composers: entries("composers"),
            artists: entries("artists"),
            venues: entries("venues"),
            weekdays: Dictionary(uniqueKeysWithValues: map("weekdays").compactMap { key, value in Int(key).map { ($0, value) } }),
            bands: map("bands"),
            signalCount: row.integer("signal_count") ?? 0
        )
    }
}
