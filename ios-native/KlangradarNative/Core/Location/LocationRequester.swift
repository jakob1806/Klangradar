import CoreLocation

enum LocationRequestError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: "Standortzugriff wurde nicht erlaubt."
        case .unavailable: "Standort konnte nicht ermittelt werden."
        }
    }
}

/// Einmalige Standortabfrage für den Onboarding-Schritt — kein
/// fortlaufendes Tracking, keine Hintergrundaktualisierung. Bündelt die
/// delegate-basierte `CLLocationManager`-API (keine native async-API dafür)
/// hinter einer einzigen `async throws`-Funktion, analog zu
/// `BiometricAuth.authenticate`.
@MainActor
final class LocationRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    func requestOnce() async throws -> CLLocationCoordinate2D {
        manager.delegate = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                finish(.failure(LocationRequestError.denied))
            @unknown default:
                finish(.failure(LocationRequestError.unavailable))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ : CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(.failure(LocationRequestError.denied))
            case .notDetermined:
                break
            @unknown default:
                finish(.failure(LocationRequestError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in finish(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
