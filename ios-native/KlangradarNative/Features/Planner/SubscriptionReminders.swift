// Erstellt von Claude Code (Nutzerwunsch 01.11.2026, Abo-Bereich erweitern).
// Seit dem Mitteilungs-Konzept vom selben Tag ("Planung: genau eine pro
// Konzert") erinnert der Server: Abo-Konzerte laufen in dieselbe
// Konzerttag-Erinnerung wie gemerkte und geplante Konzerte
// (push_candidates, user_concert_subscriptions.remind). Die anfangs lokal
// geplanten Vorabend-Mitteilungen werden hier nur noch aufgeräumt.
import Foundation
import UserNotifications

enum SubscriptionReminders {
    static func isEnabled(_ subscriptionID: UUID) async -> Bool {
        await PlannerAPI.myReminders()[subscriptionID] ?? true
    }

    /// Schaltet die Erinnerung je Abo um (fragt beim Einschalten einmalig nach
    /// der Mitteilungs-Erlaubnis). Liefert false, wenn Mitteilungen aus sind.
    @discardableResult
    static func setEnabled(_ enabled: Bool, subscription: ConcertSubscription) async -> Bool {
        await removeLegacyLocal(subscription.id)
        if enabled {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional else { return false }
        }
        try? await PlannerAPI.setReminder(subscription.id, enabled)
        return true
    }

    /// Frühere lokale Vorabend-Erinnerungen entfernen (sonst doppelt).
    static func removeLegacyLocal(_ id: UUID) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "abo-\(id.uuidString)-"
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        UserDefaults.standard.removeObject(forKey: "subscriptionReminderIDs")
    }
}
