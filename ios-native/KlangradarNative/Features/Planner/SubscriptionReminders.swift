// Erstellt von Claude Code (Nutzerwunsch 01.11.2026, Abo-Bereich erweitern):
// Erinnerung am Vortag für jedes Konzert eines eigenen Abos. Lokale
// Mitteilungen (kein Server nötig), je Abo ein- und ausschaltbar; die Auswahl
// liegt nur auf dem Gerät.
import Foundation
import UserNotifications

enum SubscriptionReminders {
    private static let defaultsKey = "subscriptionReminderIDs"
    /// iOS erlaubt höchstens 64 ausstehende lokale Mitteilungen pro App.
    private static let maxPerSubscription = 12

    static func isEnabled(_ subscriptionID: UUID) -> Bool {
        enabledIDs.contains(subscriptionID.uuidString)
    }

    private static var enabledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: defaultsKey) }
    }

    /// Schaltet die Erinnerungen ein (fragt einmalig nach der Erlaubnis) oder
    /// aus. Liefert false, wenn Mitteilungen nicht erlaubt sind.
    @discardableResult
    static func setEnabled(_ enabled: Bool, subscription: ConcertSubscription, events: [ConcertEvent]) async -> Bool {
        if !enabled {
            enabledIDs.remove(subscription.id.uuidString)
            await removeAll(subscription.id)
            return true
        }
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return false }
        enabledIDs.insert(subscription.id.uuidString)
        await schedule(subscription: subscription, events: events)
        return true
    }

    /// Plant die Erinnerungen neu (z. B. nach geänderter Wochentags-Variante).
    static func schedule(subscription: ConcertSubscription, events: [ConcertEvent]) async {
        guard isEnabled(subscription.id) else { return }
        await removeAll(subscription.id)
        let center = UNUserNotificationCenter.current()
        let calendar = KlangradarDateTime.calendar
        let upcoming = events.filter { ($0.startDate ?? .distantPast) > .now }.prefix(maxPerSubscription)
        for event in upcoming {
            guard let start = event.startDate,
                  let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)),
                  let fireAt = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore),
                  fireAt > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Morgen: \(subscription.name)"
            content.body = "\(event.title) · \(KlangradarDateTime.string(start, format: "HH:mm")) Uhr, \(event.venueName)"
            content.sound = .default
            content.threadIdentifier = "subscription-\(subscription.id.uuidString)"
            content.userInfo = ["route": "/event/\(event.slug)", "event_slug": event.slug, "kind": "subscription_reminder"]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
            let request = UNNotificationRequest(
                identifier: identifierPrefix(subscription.id) + event.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    private static func identifierPrefix(_ id: UUID) -> String { "abo-\(id.uuidString)-" }

    private static func removeAll(_ id: UUID) async {
        let center = UNUserNotificationCenter.current()
        let prefix = identifierPrefix(id)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }
}
