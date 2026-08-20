@preconcurrency import CoreLocation
@preconcurrency import MapKit

/// Punkt 20, "Kartensuche": Adress-/POI-Autovervollständigung während des
/// Tippens, dieselbe API, die Apple Maps selbst für die Suchleiste nutzt.
@MainActor
final class EditorialLocationSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // München-Region als Priorität, da hier praktisch alle Venues liegen
        // — Ergebnisse aus anderen Städten sind selten gemeint.
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.1372, longitude: 11.5755),
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
        )
    }

    func update(query: String) {
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        return try? await search.start().mapItems.first
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak self] in self?.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.suggestions = [] }
    }
}

/// Punkt 20, "GPS": einmaliger aktueller Standort, mit Rückwärts-Geocoding
/// zu Adressfeldern — genutzt vom "Meinen Standort verwenden"-Button.
@MainActor
final class EditorialCurrentLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    enum LocationError: LocalizedError {
        case denied, unavailable
        var errorDescription: String? {
            switch self {
            case .denied: "Standortzugriff wurde nicht erlaubt. Bitte in den Einstellungen aktivieren."
            case .unavailable: "Standort konnte nicht ermittelt werden."
            }
        }
    }

    func currentLocation() async throws -> CLLocation {
        manager.delegate = self
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { throw LocationError.denied }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            guard self.continuation != nil else { return }
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                self.continuation?.resume(throwing: LocationError.denied)
                self.continuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.continuation?.resume(returning: location)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: LocationError.unavailable)
            self.continuation = nil
        }
    }
}
