import Foundation
import AuthenticationServices
import UIKit

actor AuthService {
    static let callbackScheme = "de.klangradar.native"
    static let callbackURL = "de.klangradar.native://auth-callback"

    enum CallbackAction {
        case signedIn
        case passwordRecovery
    }
    private let configuration: APIConfiguration
    private let client: any HTTPClient
    private let keychain: KeychainStore
    private let sessionAccount = "supabase-session"
    private var cachedSession: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?

    init(
        configuration: APIConfiguration,
        client: any HTTPClient = URLSessionHTTPClient(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.configuration = configuration
        self.client = client
        self.keychain = keychain
    }

    func restoreOrCreateSession() async throws -> AuthSession {
        if let cachedSession, cachedSession.expirationDate > .now.addingTimeInterval(60) {
            return cachedSession
        }

        if
            let data = try? keychain.load(account: sessionAccount),
            let session = try? JSONDecoder.supabase.decode(AuthSession.self, from: data)
        {
            cachedSession = session
            if session.expirationDate > .now.addingTimeInterval(60) {
                return session
            }
            do {
                return try await deduplicatedRefresh(session.refreshToken)
            } catch {
                // Supabase-Refresh-Tokens sind Einmal-Tokens: schlägt der Refresh
                // fehl (z.B. weil er bereits verbraucht wurde), bleibt die kaputte
                // Session sonst dauerhaft in der Keychain liegen — "Erneut
                // versuchen" würde denselben ungültigen Token immer wieder lesen
                // und nie mehr durchkommen. Verworfene Session löschen und wie
                // beim allerersten Start anonym neu starten.
                cachedSession = nil
                try? keychain.delete(account: sessionAccount)
                return try await signInAnonymously()
            }
        }

        return try await signInAnonymously()
    }

    /// Bündelt gleichzeitige Refresh-Aufrufe auf denselben Token in eine
    /// einzige In-Flight-Anfrage. Ohne das würden z. B. zwei parallele
    /// `bootstrap()`-Aufrufe (RootTabView + ProfileView beim App-Start) mit
    /// demselben, noch nicht rotierten Refresh-Token beim Server ankommen —
    /// der zweite bekäme dann "Refresh Token Not Found", weil der erste ihn
    /// bereits verbraucht/rotiert hat.
    private func deduplicatedRefresh(_ token: String) async throws -> AuthSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await refresh(token) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func signInAnonymously() async throws -> AuthSession {
        try await performSessionRequest(path: "signup", body: ["data": .object([:])])
    }

    /// Erstellt einen Account mit Passwort. Solange `enable_confirmations`
    /// aktiv ist (siehe config.toml), liefert Supabase hierfür KEINE Session
    /// zurück — nur den angelegten, noch unbestätigten Nutzer. Erst
    /// `verifySignupCode` nach Eingabe des per Mail
    /// verschickten Codes gibt eine echte Session.
    func signUp(email: String, password: String) async throws -> AuthUser {
        let data = try await perform(
            path: "signup?redirect_to=\(Self.encodedCallbackURL)",
            body: [
                "email": .string(email),
                "password": .string(password)
            ]
        )
        return try JSONDecoder.supabase.decode(AuthUser.self, from: data)
    }

    func signInWithPassword(email: String, password: String) async throws -> AuthSession {
        try await performSessionRequest(
            path: "token?grant_type=password",
            body: [
                "email": .string(email),
                "password": .string(password)
            ]
        )
    }

    /// Verschickt den sicheren Recovery-Link. Der Link öffnet die App über
    /// `callbackURL`; erst diese Callback-Session darf das Passwort ändern.
    func requestPasswordReset(email: String) async throws {
        _ = try await perform(
            path: "recover?redirect_to=\(Self.encodedCallbackURL)",
            body: ["email": .string(email)]
        )
    }

    /// Eigener Endpoint (`/resend`) statt `/otp` — die Signup-Bestätigung
    /// ist ein anderer Mail-Typ als der Login-Code, `/otp` würde für einen
    /// bereits (unbestätigt) existierenden Nutzer eine Magic-Link-Mail statt
    /// die Signup-Bestätigung erneut verschicken.
    func resendSignupConfirmation(email: String) async throws {
        _ = try await perform(
            path: "resend",
            body: [
                "type": .string("signup"),
                "email": .string(email)
            ]
        )
    }

    /// Bestätigt ausschließlich den sechsstelligen Registrierungs-Code.
    /// Passwort-Recovery läuft absichtlich nicht über diesen Endpoint.
    func verifySignupCode(_ code: String, email: String) async throws -> AuthSession {
        try await performSessionRequest(
            path: "verify",
            body: [
                "email": .string(email),
                "token": .string(code),
                "type": .string("signup")
            ]
        )
    }

    func signInWithGoogle() async throws -> AuthSession {
        try await signInWithOAuth(provider: "google")
    }

    func signInWithApple() async throws -> AuthSession {
        try await signInWithOAuth(provider: "apple")
    }

    func enabledOAuthProviders() async throws -> Set<String> {
        var request = authorizedRequest(path: "settings", token: configuration.supabaseAnonKey)
        request.httpMethod = "GET"
        let (data, response) = try await client.data(for: request)
        guard 200..<300 ~= response.statusCode else { throw APIError.httpStatus(response.statusCode, "Login-Anbieter konnten nicht geladen werden") }
        let settings = try JSONDecoder().decode(AuthProviderSettings.self, from: data)
        return Set(settings.external.compactMap { $0.value ? $0.key : nil })
    }

    func signOut() async throws {
        if let session = cachedSession {
            var request = authorizedRequest(path: "logout", token: session.accessToken)
            request.httpMethod = "POST"
            _ = try await client.data(for: request)
        }
        cachedSession = nil
        try keychain.delete(account: sessionAccount)
    }

    func updateEmail(_ email: String) async throws {
        try await updateUser(["email": .string(email)])
    }

    func updatePassword(_ password: String) async throws {
        try await updateUser(["password": .string(password)])
    }

    /// Übernimmt die Session aus einem Supabase-Mail-Link. Recovery-Links
    /// enthalten die Tokens im URL-Fragment; anschließend darf der Nutzer
    /// genau einmal ein neues Passwort festlegen.
    func handleCallback(_ url: URL) async throws -> CallbackAction {
        guard url.scheme == Self.callbackScheme, url.host == "auth-callback" else {
            throw AuthServiceError.invalidCallback
        }
        let values = Self.callbackValues(from: url)
        if let message = values["error_description"] ?? values["error"] {
            throw AuthServiceError.server(Self.friendlyMessage(message))
        }
        guard let accessToken = values["access_token"], let refreshToken = values["refresh_token"] else {
            throw AuthServiceError.invalidCallback
        }
        _ = try await session(accessToken: accessToken, refreshToken: refreshToken, values: values)
        return values["type"] == "recovery" ? .passwordRecovery : .signedIn
    }

    private func updateUser(_ values: JSONObject) async throws {
        guard let session = cachedSession else { throw AuthStoreError.unavailable }
        var request = authorizedRequest(path: "user", token: session.accessToken)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(values)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await client.data(for: request)
        guard 200..<300 ~= response.statusCode else {
            throw AuthServiceError.server(Self.errorMessage(from: data, statusCode: response.statusCode))
        }
    }

    private func refresh(_ token: String) async throws -> AuthSession {
        try await performSessionRequest(
            path: "token?grant_type=refresh_token",
            body: ["refresh_token": .string(token)]
        )
    }

    private func signInWithOAuth(provider: String) async throws -> AuthSession {
        var components = URLComponents(
            url: configuration.supabaseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: Self.callbackURL)
        ]
        guard let authorizeURL = components.url else { throw AuthStoreError.unavailable }
        let callback = try await OAuthWebAuthentication.authenticate(url: authorizeURL, callbackScheme: Self.callbackScheme)
        let values = Self.callbackValues(from: callback)
        if let message = values["error_description"] ?? values["error"] {
            throw AuthServiceError.server(Self.friendlyMessage(message))
        }
        guard let accessToken = values["access_token"], let refreshToken = values["refresh_token"] else {
            throw AuthServiceError.invalidCallback
        }
        return try await session(accessToken: accessToken, refreshToken: refreshToken, values: values)
    }

    private func session(accessToken: String, refreshToken: String, values: [String: String]) async throws -> AuthSession {
        let expiresIn = Int(values["expires_in"] ?? "3600") ?? 3600
        var userRequest = authorizedRequest(path: "user", token: accessToken)
        userRequest.httpMethod = "GET"
        let (userData, response) = try await client.data(for: userRequest)
        guard 200..<300 ~= response.statusCode else {
            throw AuthServiceError.server(Self.errorMessage(from: userData, statusCode: response.statusCode))
        }
        let user = try JSONDecoder.supabase.decode(AuthUser.self, from: userData)
        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            expiresAt: Int(Date().timeIntervalSince1970) + expiresIn,
            tokenType: values["token_type"] ?? "bearer",
            user: user
        )
        cachedSession = session
        try keychain.save(try JSONEncoder().encode(session), account: sessionAccount)
        return session
    }

    private static func callbackValues(from url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        if let fragment = components?.fragment {
            items += URLComponents(string: "?\(fragment)")?.queryItems ?? []
        }
        return items.reduce(into: [:]) { values, item in
            if let value = item.value { values[item.name] = value }
        }
    }

    private static var encodedCallbackURL: String {
        callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? callbackURL
    }

    private func performSessionRequest(
        path: String,
        body: JSONObject
    ) async throws -> AuthSession {
        let data = try await perform(path: path, body: body)
        let session = try JSONDecoder.supabase.decode(AuthSession.self, from: data)
        cachedSession = session
        try keychain.save(try JSONEncoder().encode(session), account: sessionAccount)
        return session
    }

    private func perform(path: String, body: JSONObject) async throws -> Data {
        var request = authorizedRequest(path: path, token: configuration.supabaseAnonKey)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await client.data(for: request)
        guard 200..<300 ~= response.statusCode else {
            throw AuthServiceError.server(Self.errorMessage(from: data, statusCode: response.statusCode))
        }
        return data
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        let response = try? JSONDecoder().decode(AuthErrorResponse.self, from: data)
        let original = response?.message ?? response?.msg ?? response?.errorDescription ?? response?.error
        guard let original else { return "Das hat leider nicht funktioniert. Bitte versuche es erneut." }
        return friendlyMessage(original, statusCode: statusCode)
    }

    private static func friendlyMessage(_ message: String, statusCode: Int = 400) -> String {
        let value = message.lowercased()
        if value.contains("invalid login credentials") { return "E-Mail-Adresse oder Passwort ist nicht korrekt." }
        if value.contains("email not confirmed") { return "Bitte bestätige zuerst deine E-Mail-Adresse." }
        if value.contains("user already registered") || value.contains("already been registered") { return "Für diese E-Mail-Adresse gibt es bereits einen Account. Melde dich an oder setze dein Passwort zurück." }
        if value.contains("password") && (value.contains("weak") || value.contains("least")) { return "Das Passwort erfüllt die Anforderungen noch nicht." }
        if value.contains("rate limit") || statusCode == 429 { return "Zu viele Versuche. Bitte warte kurz und probiere es dann erneut." }
        if value.contains("expired") { return "Dieser Link oder Code ist abgelaufen. Fordere bitte einen neuen an." }
        return message
    }

    private func authorizedRequest(path: String, token: String) -> URLRequest {
        let parts = path.split(separator: "?", maxSplits: 1).map(String.init)
        var components = URLComponents(
            url: configuration.supabaseURL
            .appendingPathComponent("auth/v1")
            .appendingPathComponent(parts[0]),
            resolvingAgainstBaseURL: false
        )!
        if parts.count == 2 {
            components.percentEncodedQuery = parts[1]
        }
        let url = components.url!
        var request = URLRequest(url: url)
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

private struct AuthErrorResponse: Decodable {
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case message, msg, error
        case errorDescription = "error_description"
    }
}

private enum AuthServiceError: LocalizedError {
    case invalidCallback
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidCallback: "Der Anmeldelink ist ungültig oder unvollständig. Fordere bitte einen neuen Link an."
        case let .server(message): message
        }
    }
}

private struct AuthProviderSettings: Decodable {
    let external: [String: Bool]
}

@MainActor
private final class OAuthWebAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    static func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let helper = OAuthWebAuthentication()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                helper.session = nil
                if let error { continuation.resume(throwing: error); return }
                guard let callbackURL else {
                    continuation.resume(throwing: APIError.httpStatus(400, "Anmeldung wurde ohne Rueckmeldung beendet."))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            helper.session = session
            session.presentationContextProvider = helper
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                helper.session = nil
                continuation.resume(throwing: APIError.httpStatus(500, "Anmeldefenster konnte nicht geoeffnet werden."))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
