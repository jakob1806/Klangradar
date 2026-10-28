import Combine
import Foundation
import UIKit
import UserNotifications

/// Registriert das Gerät bei Apples Push-Dienst und speichert das Token in
/// `push_tokens` (als "apns:prod:<hex>" bzw. "apns:dev:<hex>"), damit die
/// serverseitigen Benachrichtigungen (Erinnerungen, gefolgte Künstler,
/// Programmänderungen) auch die native iOS-App erreichen.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()
    private var client: SupabaseRESTClient?
    private weak var auth: AuthStore?
    private var deviceToken: String?
    private var lastUpload: (token: String, userID: UUID)?
    private var cancellable: AnyCancellable?

    func configure(client: SupabaseRESTClient?, auth: AuthStore) {
        self.client = client
        self.auth = auth
        // Bei Kontowechsel (anonym → angemeldet) das Token neu zuordnen.
        cancellable = auth.$state.sink { [weak self] _ in
            Task { @MainActor in self?.uploadIfPossible() }
        }
        Task { await registerIfAuthorized() }
    }

    /// Nur registrieren, wenn Mitteilungen bereits erlaubt sind — die
    /// Erlaubnis selbst fragt das Onboarding bzw. die Einstellungen ab.
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken data: Data) {
        #if DEBUG
        let environment = "dev"
        #else
        let environment = "prod"
        #endif
        deviceToken = "apns:\(environment):" + data.map { String(format: "%02x", $0) }.joined()
        uploadIfPossible()
    }

    private func uploadIfPossible() {
        guard let client, let deviceToken, let session = auth?.session else { return }
        if let lastUpload, lastUpload.token == deviceToken, lastUpload.userID == session.user.id { return }
        lastUpload = (deviceToken, session.user.id)
        let token = session.accessToken
        Task.detached {
            let _: JSONValue? = try? await client.rpc(
                "register_push_token",
                parameters: ["p_token": .string(deviceToken), "p_platform": .string("ios")],
                accessToken: token
            )
        }
    }

    // MARK: - Mitteilungs-Kategorien und Schnellaktionen (push-dispatcher)

    nonisolated static let actionSave = "SAVE"
    nonisolated static let actionGoing = "GOING"
    nonisolated static let actionAskFriends = "ASK_FRIENDS"
    nonisolated static let actionOpen = "OPEN"
    /// Freundschaftsanfrage direkt aus der Mitteilung beantworten (notify-social, Kategorie FRIEND_REQUEST).
    nonisolated static let actionAcceptFriend = "ACCEPT_FRIEND"
    nonisolated static let actionDeclineFriend = "DECLINE_FRIEND"
    nonisolated static let backgroundActions: Set<String> = [actionSave, actionGoing, actionAcceptFriend, actionDeclineFriend]

    /// Kategorien der Server-Mitteilungen; die Attendance-Kategorie wird
    /// vom AppDelegate ergänzt.
    nonisolated static var serverCategories: [UNNotificationCategory] {
        let save = UNNotificationAction(identifier: actionSave, title: "Merken", options: [], icon: UNNotificationActionIcon(systemImageName: "heart"))
        let going = UNNotificationAction(identifier: actionGoing, title: "Ich gehe hin", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let ask = UNNotificationAction(identifier: actionAskFriends, title: "Freunde fragen", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "person.2"))
        let route = UNNotificationAction(identifier: actionOpen, title: "Anreise & Zeitplan", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "map"))
        let rate = UNNotificationAction(identifier: actionOpen, title: "Bewerten", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "star"))
        let acceptFriend = UNNotificationAction(identifier: actionAcceptFriend, title: "Annehmen", options: [.authenticationRequired], icon: UNNotificationActionIcon(systemImageName: "person.badge.plus"))
        let declineFriend = UNNotificationAction(identifier: actionDeclineFriend, title: "Ablehnen", options: [.destructive], icon: UNNotificationActionIcon(systemImageName: "xmark"))
        return [
            UNNotificationCategory(identifier: "FRIEND_REQUEST", actions: [acceptFriend, declineFriend], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "EVENT", actions: [save, going, ask], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "CONCERT_DAY", actions: [route, ask], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "RATE", actions: [rate], intentIdentifiers: [], options: []),
        ]
    }

    /// Öffnen oder Schnellaktion an den Server melden (push_log.opened_at:
    /// Grundlage für das Lernen, welche Mitteilungen ankommen) und
    /// Hintergrund-Aktionen (Merken, Ich gehe hin) direkt ausführen.
    func handle(fields: [String: String], action: String) async {
        guard let client, let session = auth?.session else { return }
        let token = session.accessToken
        if let rawLogID = fields["push_log_id"], let logID = Double(rawLogID) {
            let reported = action == UNNotificationDefaultActionIdentifier ? JSONValue.null : JSONValue.string(action)
            let _: JSONValue? = try? await client.rpc("push_opened", parameters: ["p_log_id": .number(logID), "p_action": reported], accessToken: token)
        }
        if action == Self.actionAcceptFriend || action == Self.actionDeclineFriend {
            guard let actor = fields["actor_id"] else { return }
            let _: JSONValue? = try? await client.rpc(
                "respond_friend_request",
                parameters: ["p_user_id": .string(actor), "p_accept": .bool(action == Self.actionAcceptFriend)],
                accessToken: token
            )
            await SocialStore.shared.refresh()
            return
        }
        guard let eventID = fields["event_id"], !session.user.isAnonymous.orFalse else { return }
        switch action {
        case Self.actionSave, Self.actionGoing:
            _ = try? await client.upsert(
                table: "favorites",
                values: ["user_id": .string(session.user.id.uuidString), "event_id": .string(eventID), "status": .string(action == Self.actionGoing ? "attending" : "interested")],
                accessToken: token,
                conflictColumns: "user_id,event_id"
            )
        default:
            break
        }
    }
}

private extension Optional where Wrapped == Bool {
    var orFalse: Bool { self ?? false }
}
