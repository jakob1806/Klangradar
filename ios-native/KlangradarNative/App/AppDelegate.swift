import UIKit
import UserNotifications

/// Ausschließlich für AttendanceLocationMonitor: Region-Monitoring liefert
/// beim Betreten einer überwachten Spielstätte eine lokale Benachrichtigung
/// (siehe dort), auch wenn die App im Hintergrund oder nicht gestartet ist.
/// UNUserNotificationCenterDelegate braucht dafür einen echten
/// UIApplicationDelegate-Anschlusspunkt — SwiftUIs @main App-Lifecycle
/// bietet dafür keinen eigenen Hook.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let confirmAction = UNNotificationAction(identifier: "ATTENDANCE_YES", title: "Ja, war ich", options: [.foreground])
        let declineAction = UNNotificationAction(identifier: "ATTENDANCE_NO", title: "Nein", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: AttendanceLocationMonitor.notificationCategoryID,
            actions: [confirmAction, declineAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        return true
    }

    // NICHT @MainActor-isoliert implementiert (wie bei AddToCalendarView.
    // Coordinator): UNUserNotificationCenterDelegate selbst ist nicht
    // isoliert, eine MainActor-isolierte Konformität dazu verletzt unter
    // Swift 6 strict concurrency die Protokoll-Isolation, da UIKit die
    // Delegate-Parameter (UNNotification etc.) nicht als Sendable deklariert.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        guard let eventIDString = userInfo[AttendanceLocationMonitor.eventIDUserInfoKey] as? String,
              let eventID = UUID(uuidString: eventIDString) else { return }
        guard actionIdentifier != "ATTENDANCE_NO" else { return }
        let title = userInfo[AttendanceLocationMonitor.eventTitleUserInfoKey] as? String ?? "diesem Konzert"
        await MainActor.run {
            AttendanceLocationMonitor.shared.presentConfirmation(eventID: eventID, title: title)
        }
    }
}
