import CoreLocation
import Foundation

/// Sitzungsweiter Stadt-Filter für Karte/Suche/Home (siehe
/// CitySwitcherView) -- `selectedCity == nil` bedeutet "alle Städte",
/// analog zum Flutter-Pendant `selectedCityRegionProvider`
/// (app/lib/core/regions/region_providers.dart). Seedet sich EINMALIG aus
/// `profiles.preferred_region_id`, sobald ein Nutzer angemeldet ist UND
/// noch keine eigene Auswahl in dieser Sitzung getroffen wurde -- eine
/// bewusste spätere Auswahl wird dadurch nie überschrieben.
@MainActor
final class CityStore: ObservableObject {
    @Published private(set) var activeCities: [RegionOption] = []
    @Published var selectedCity: RegionOption?
    @Published private(set) var isLoading = false

    private let auth: AuthStore
    private let repository: UserRepository?
    private var didSeedFromPreference = false

    init(auth: AuthStore, repository: UserRepository?) {
        self.auth = auth
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        activeCities = (try? await repository?.activeRegions()) ?? []
        await seedFromPreferredRegionIfNeeded()
        // Ohne eigene oder gespeicherte Auswahl soll die App wie zuvor mit
        // einer konkreten Stadt starten statt mit dem Platzhalter "Stadt" im
        // Chip -- "Alle Städte" bleibt eine bewusste Auswahl über die Karte.
        if selectedCity == nil, !didSeedFromPreference {
            selectedCity = activeCities.first
        }
    }

    /// Explizite Nutzerauswahl (z.B. aus CitySwitcherView) -- persistiert bei
    /// angemeldeten Nutzern als neue `profiles.preferred_region_id`
    /// (dieselbe Spalte, die auch das Onboarding setzt), bleibt sonst nur
    /// In-Memory für die laufende Sitzung.
    func select(_ city: RegionOption?) {
        selectedCity = city
        didSeedFromPreference = true
        guard let repository, let userID = auth.userID, let token = auth.accessToken, let city else { return }
        Task { try? await repository.setPreferredRegion(regionID: city.id, userID: userID, token: token) }
    }

    /// Nächstgelegene aktive Stadt zur übergebenen Koordinate, per
    /// Luftlinie gegen `regions.latitude/longitude` -- kein Geocoding
    /// nötig, da gegen eine kleine, bekannte Städteliste gematcht wird statt
    /// gegen beliebige Adressen.
    func nearestCity(to coordinate: CLLocationCoordinate2D) -> RegionOption? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return activeCities
            .compactMap { city -> (RegionOption, CLLocationDistance)? in
                guard let lat = city.latitude, let lng = city.longitude else { return nil }
                return (city, target.distance(from: CLLocation(latitude: lat, longitude: lng)))
            }
            .min { $0.1 < $1.1 }?.0
    }

    private func seedFromPreferredRegionIfNeeded() async {
        guard !didSeedFromPreference, selectedCity == nil,
              let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        didSeedFromPreference = true
        guard let preferredID = try? await repository.preferredRegionID(userID: userID, token: token) else { return }
        selectedCity = activeCities.first { $0.id == preferredID }
    }
}
