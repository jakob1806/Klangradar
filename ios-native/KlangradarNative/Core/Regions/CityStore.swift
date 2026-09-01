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
    // Nutzerfeedback: "App öffnet sich immer in Berlin statt der gewählten
    // Stadt" -- RootTabView startet auth.bootstrap() und cityStore.load()
    // als parallele .task-Modifier, load() lief also oft schon los, bevor
    // die Session (und damit auth.accessToken) wiederhergestellt war.
    // seedFromPreferredRegionIfNeeded() bricht dann mangels Token sofort ab,
    // und der Default (erste aktive Stadt, alphabetisch Berlin) greift --
    // ohne Nachkorrektur, sobald die Session eintrifft. Dieses Flag
    // unterscheidet "Default mangels Zeit gesetzt" von "bewusst leer"
    // (nie angemeldet/keine Präferenz), damit reseedFromAuthIfNeeded()
    // gezielt nachbessern kann, ohne eine echte spätere Auswahl anzutasten.
    private var didApplyDefaultFallback = false

    init(auth: AuthStore, repository: UserRepository?) {
        self.auth = auth
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if activeCities.isEmpty {
            activeCities = (try? await repository?.activeRegions()) ?? []
        }
        await seedFromPreferredRegionIfNeeded()
        // Ohne eigene oder gespeicherte Auswahl soll die App wie zuvor mit
        // einer konkreten Stadt starten statt mit dem Platzhalter "Stadt" im
        // Chip -- "Alle Städte" bleibt eine bewusste Auswahl über die Karte.
        if selectedCity == nil, !didSeedFromPreference {
            selectedCity = activeCities.first
            didApplyDefaultFallback = true
        }
    }

    /// Erneuter Versuch, nachdem die Auth-Session fertig geladen ist --
    /// siehe `didApplyDefaultFallback`-Doku oben. Von RootTabView bei
    /// `auth.userID`-Änderung aufgerufen; ohne Wirkung, falls schon eine
    /// echte Präferenz griff oder eine bewusste Auswahl getroffen wurde.
    func reseedFromAuthIfNeeded() async {
        guard didApplyDefaultFallback, !didSeedFromPreference,
              let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        guard let preferredID = try? await repository.preferredRegionID(userID: userID, token: token),
              let match = activeCities.first(where: { $0.id == preferredID }) else { return }
        didSeedFromPreference = true
        didApplyDefaultFallback = false
        selectedCity = match
    }

    /// Explizite Nutzerauswahl (z.B. aus CitySwitcherView) -- persistiert bei
    /// angemeldeten Nutzern als neue `profiles.preferred_region_id`
    /// (dieselbe Spalte, die auch das Onboarding setzt), bleibt sonst nur
    /// In-Memory für die laufende Sitzung.
    func select(_ city: RegionOption?) {
        selectedCity = city
        didSeedFromPreference = true
        didApplyDefaultFallback = false
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
