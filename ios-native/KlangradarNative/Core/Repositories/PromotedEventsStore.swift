import Foundation

/// Aktive, bezahlte Promotionen. Zwei Aufgaben:
/// 1. `ids`: `EventArtwork` blendet dafür oben links ein kleines
///    "Anzeige"-Label ein — Werbung muss als solche erkennbar sein.
/// 2. Platzierung im Feed: Hero (`homepage_feature`), erste Karte der
///    Empfehlungs-Schiene (`local_spotlight`), erste Karte in "Konzerte
///    entdecken" (`featured`) und vorne in Listen/Kalender (`standard`).
///    Mehrere Buchungen derselben Platzierung rotieren täglich.
@MainActor
final class PromotedEventsStore: ObservableObject {
    static let shared = PromotedEventsStore()
    @Published private(set) var ids: Set<UUID> = []
    @Published private(set) var eventsByPlacement: [String: [ConcertEvent]] = [:]
    private var lastLoaded: Date?

    func load(client: SupabaseRESTClient?, repository: (any EventRepository)?) async {
        guard let client else { return }
        // Fehler bewusst still: ohne Daten gibt es schlicht keine Platzierung.
        guard let rows: [JSONObject] = try? await client.rpc("active_event_promotions") else { return }
        var placementIDs: [String: [UUID]] = [:]
        for row in rows {
            guard let id = row.string("event_id").flatMap(UUID.init(uuidString:)), let placement = row.string("placement") else { continue }
            placementIDs[placement, default: []].append(id)
        }
        let allIDs = Set(placementIDs.values.flatMap { $0 })
        ids = allIDs
        lastLoaded = .now
        guard let repository, !allIDs.isEmpty else { eventsByPlacement = [:]; return }
        let loaded = (try? await repository.events(ids: Array(allIDs))) ?? []
        let enriched = (try? await repository.enrichingImages(in: loaded)) ?? loaded
        let byID = Dictionary(enriched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        eventsByPlacement = placementIDs.mapValues { $0.compactMap { byID[$0] } }
    }

    func refreshIfStale(client: SupabaseRESTClient?, repository: (any EventRepository)?) async {
        if let lastLoaded, Date.now.timeIntervalSince(lastLoaded) < 600 { return }
        await load(client: client, repository: repository)
    }

    /// Beworbene Events einer Platzierung für die gewählte Stadt, täglich rotiert.
    func events(for placement: String, regionID: UUID?) -> [ConcertEvent] {
        let candidates = (eventsByPlacement[placement] ?? []).filter { event in
            (regionID == nil || event.venues?.cityId == nil || event.venues?.cityId == regionID)
                && (event.startDate ?? .distantPast) > .now
        }
        guard candidates.count > 1 else { return candidates }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        let offset = day % candidates.count
        return Array(candidates[offset...] + candidates[..<offset])
    }

    /// Setzt beworbene Events an den Anfang einer Liste (ohne Duplikate).
    func boosting(
        _ list: [ConcertEvent],
        placement: String,
        regionID: UUID?,
        maxPromoted: Int = 1,
        where include: (ConcertEvent) -> Bool = { _ in true }
    ) -> [ConcertEvent] {
        let promoted = Array(events(for: placement, regionID: regionID).filter(include).prefix(maxPromoted))
        guard !promoted.isEmpty else { return list }
        let promotedIDs = Set(promoted.map(\.id))
        return promoted + list.filter { !promotedIDs.contains($0.id) }
    }
}
