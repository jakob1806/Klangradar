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
}
