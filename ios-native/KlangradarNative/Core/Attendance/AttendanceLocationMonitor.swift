import CoreLocation
import UserNotifications

/// Kandidat für die passive Besuchs-Erkennung: ein gemerktes Event mit
/// bekannter Spielstätte, dessen Beginn innerhalb des Überwachungsfensters
/// liegt (siehe `UserRepository.upcomingFavoritesWithVenue`).
struct AttendanceCandidate: Sendable {
    let eventID: UUID
    let title: String
    let startDate: Date
    let venueID: UUID
}

/// Nutzerwunsch: statt eines Standort-Checks, der das manuelle "Als besucht
/// markieren" blockiert (siehe EventDetailView), läuft die Standort-
/// Erkennung jetzt passiv im Hintergrund per Geofencing. Sie markiert
/// NIEMALS selbstständig als besucht — sie löst nur eine lokale
/// Benachrichtigung aus, die zu einem eigenen Bestätigungs-Popup
/// (Ja/Nein, siehe AttendanceConfirmationPrompt) führt.
///
/// Bewusst kein fortlaufendes Standort-Tracking: `startMonitoring(for:)`
/// weckt die App nur beim Betreten einer der (max. 20 gleichzeitig
/// erlaubten) überwachten Regionen, unabhängig davon, ob die App läuft.
@MainActor
final class AttendanceLocationMonitor: NSObject, CLLocationManagerDelegate, ObservableObject {
    static let shared = AttendanceLocationMonitor()

    nonisolated static let notificationCategoryID = "ATTENDANCE_CONFIRM"
    nonisolated static let eventIDUserInfoKey = "attendanceEventID"
    nonisolated static let eventTitleUserInfoKey = "attendanceTitle"

    struct PendingConfirmation: Identifiable {
        let eventID: UUID
        let title: String
        var id: UUID { eventID }
    }

    @Published var pendingConfirmation: PendingConfirmation?

    private let manager = CLLocationManager()
    private var repository: UserRepository?
    private weak var auth: AuthStore?
    private var regionMeta: [String: (eventID: UUID, title: String, start: Date)] = [:]

    private override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
    }

    func configure(repository: UserRepository?, auth: AuthStore) {
        self.repository = repository
        self.auth = auth
    }

    func requestAlwaysAuthorizationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// Aktualisiert die überwachten Regionen anhand der gemerkten,
    /// bevorstehenden Events der Nutzerin. iOS erlaubt maximal 20 gleich-
    /// zeitig überwachte Regionen pro App — deshalb bewusst auf Events
    /// begrenzt, die in den nächsten 24h beginnen oder gerade laufen.
    func refresh() async {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        regionMeta.removeAll()

        guard manager.authorizationStatus == .authorizedAlways,
              let repository, let auth, let userID = auth.userID, let token = auth.accessToken else { return }
        let candidates = (try? await repository.upcomingFavoritesWithVenue(userID: userID, token: token)) ?? []

        var resolvedVenues: [UUID: VenueLocation] = [:]
        for candidate in candidates.prefix(18) {
            let venue: VenueLocation?
            if let cached = resolvedVenues[candidate.venueID] {
                venue = cached
            } else {
                venue = try? await repository.venueLocation(id: candidate.venueID)
                if let venue { resolvedVenues[candidate.venueID] = venue }
            }
            guard let venue else { continue }
            let identifier = "attendance-\(candidate.eventID.uuidString)"
            let region = CLCircularRegion(center: venue.coordinate, radius: 150, identifier: identifier)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
            regionMeta[identifier] = (candidate.eventID, candidate.title, candidate.startDate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        Task { @MainActor in await handleEntry(identifier: identifier) }
    }

    @MainActor
    private func handleEntry(identifier: String) async {
        guard let meta = regionMeta[identifier] else { return }
        let now = Date()
        // Fenster: 2h vor bis 5h nach Beginn — deckt frühes Eintreffen und
        // längere Programme/Pausen ab, ohne beliebige spätere Besuche am
        // selben Ort fälschlich zuzuordnen.
        guard now >= meta.start.addingTimeInterval(-2 * 3600), now <= meta.start.addingTimeInterval(5 * 3600) else { return }
        guard let repository, let auth, let userID = auth.userID, let token = auth.accessToken else { return }
        if (try? await repository.hasAttended(eventID: meta.eventID, userID: userID, token: token)) == true { return }

        let content = UNMutableNotificationContent()
        content.title = "Bist du gerade hier?"
        content.body = "Warst du bei „\(meta.title)“? Tippe, um zu bestätigen."
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategoryID
        content.userInfo = [Self.eventIDUserInfoKey: meta.eventID.uuidString, Self.eventTitleUserInfoKey: meta.title]
        let request = UNNotificationRequest(identifier: "attendance-prompt-\(meta.eventID.uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func presentConfirmation(eventID: UUID, title: String) {
        pendingConfirmation = PendingConfirmation(eventID: eventID, title: title)
    }

    func confirmPendingAttendance(accepted: Bool) async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        guard accepted, let repository, let auth, let userID = auth.userID, let token = auth.accessToken else { return }
        try? await repository.setAttended(eventID: pending.eventID, attended: true, attendedAt: nil, verificationType: "location", userID: userID, token: token)
        Haptics.strong()
    }
}
