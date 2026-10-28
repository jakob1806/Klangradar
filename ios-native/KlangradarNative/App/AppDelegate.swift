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
        UNUserNotificationCenter.current().setNotificationCategories(Set([category] + PushRegistration.serverCategories))
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushRegistration.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push-Registrierung fehlgeschlagen: \(error.localizedDescription)")
    }

    // Completion-Handler-Varianten statt `async`: Die async-Varianten
    // stürzten beim Tippen auf eine Mitteilung ab (Nutzermeldung 23.10.2026):
    // iOS ruft den Delegate auf dem Main-Thread, der von Swift erzeugte
    // async-Thunk ruft den Completion-Handler aber von einem Hintergrund-
    // Thread zurück (_dispatch_assert_queue_fail). Hier werden nur Strings
    // herausgelöst, der Handler sofort aufgerufen und die Arbeit auf dem
    // MainActor erledigt.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        // Nur Strings weitergeben (userInfo ist nicht Sendable).
        let fields = userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        completionHandler()
        Task { @MainActor in
            await AppDelegate.handleNotification(fields: fields, action: actionIdentifier)
        }
    }

    /// Server-Push (push-dispatcher, Erinnerung, Änderung): Öffnen bzw.
    /// Schnellaktion melden; Merken/Ich gehe hin laufen im Hintergrund,
    /// alles andere öffnet das Konzert (Freunde fragen: mit Planungsdialog).
    /// Ohne `route`: lokale Anwesenheitsabfrage (AttendanceLocationMonitor).
    @MainActor
    private static func handleNotification(fields: [String: String], action actionIdentifier: String) async {
        if let route = fields["route"] {
            if actionIdentifier == PushRegistration.actionAskFriends, let slug = fields["event_slug"] {
                DeepLinkRouter.shared.pendingPlanForSlug = slug
            }
            let opensApp = !PushRegistration.backgroundActions.contains(actionIdentifier)
            if opensApp { _ = DeepLinkRouter.shared.handle(route: route) }
            await PushRegistration.shared.handle(fields: fields, action: actionIdentifier)
            return
        }
        guard let eventIDString = fields[AttendanceLocationMonitor.eventIDUserInfoKey],
              let eventID = UUID(uuidString: eventIDString) else { return }
        guard actionIdentifier != "ATTENDANCE_NO" else { return }
        let title = fields[AttendanceLocationMonitor.eventTitleUserInfoKey] ?? "diesem Konzert"
        AttendanceLocationMonitor.shared.presentConfirmation(eventID: eventID, title: title)
    }
}
