import Foundation

/// Lokale Persistenz für Favoriten (Nutzeranfrage Punkt 12, "Offline-
/// Favoriten"/"Konfliktbehandlung") — Pendant zu Flutters FavoritesCache
/// (app/lib/core/favorites/favorites_cache.dart). Der zuletzt vom Server
/// bestätigte Stand plus ausstehende, noch nicht synchronisierte Toggles.
///
/// Konfliktstrategie: pro Event nur der jeweils letzte gewünschte Zustand
/// (`[UUID: Bool]` statt einer Op-Liste) — mehrfaches Umschalten desselben
/// Events offline kollabiert auf den finalen Wunschzustand ("letzter
/// Schreibzugriff gewinnt", die einzig sinnvolle Regel ohne serverseitige
/// updated_at-Spalte auf `favorites`).
enum FavoritesCache {
    private static let knownKey = "favoritesCache.knownIDs"
    private static let pendingKey = "favoritesCache.pending"

    static func knownIDs() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: knownKey) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func saveKnownIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: knownKey)
    }

    static func pendingChanges() -> [UUID: Bool] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let raw = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    static func savePendingChanges(_ pending: [UUID: Bool]) {
        let raw = Dictionary(uniqueKeysWithValues: pending.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    /// Bekannter Serverstand plus ausstehende lokale Änderungen übereinander.
    static func effectiveIDs() -> Set<UUID> {
        var effective = knownIDs()
        for (id, wantsFavorited) in pendingChanges() {
            if wantsFavorited { effective.insert(id) } else { effective.remove(id) }
        }
        return effective
    }
}
