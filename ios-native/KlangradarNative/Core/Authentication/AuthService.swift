import Foundation
import AuthenticationServices
import UIKit

actor AuthService {
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
    /// `verifyEmailCode(type: "signup")` nach Eingabe des per Mail
    /// verschickten Codes gibt eine echte Session.
    func signUp(email: String, password: String) async throws -> AuthUser {
        let data = try await perform(
            path: "signup",
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

    /// Löst den "Passwort vergessen"-Mailversand aus. Der darin enthaltene
    /// Code wird wie bei der Signup-Bestätigung über
    /// `verifyEmailCode(type: "recovery")` eingelöst — das liefert eine
    /// kurzlebige Session, mit der anschließend `updatePassword(_:)` das
    /// neue Passwort setzt.
    func requestPasswordReset(email: String) async throws {
        _ = try await perform(path: "recover", body: ["email": .string(email)])
    }

    func sendEmailCode(to email: String) async throws {
        _ = try await perform(
            path: "otp",
            body: [
                "email": .string(email),
                "create_user": .bool(true)
            ]
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

    /// `type` unterscheidet, welchen Code-Versand Supabase gerade bestätigt:
    /// "email" (Login-Code über `sendEmailCode`), "signup" (Bestätigung
    /// nach `signUp`) oder "recovery" (nach `requestPasswordReset`).
    func verifyEmailCode(_ code: String, email: String, type: String = "email") async throws -> AuthSession {
        try await performSessionRequest(
            path: "verify",
            body: [
                "email": .string(email),
                "token": .string(code),
                "type": .string(type)
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

    private func updateUser(_ values: JSONObject) async throws {
        guard let session = cachedSession else { throw AuthStoreError.unavailable }
        var request = authorizedRequest(path: "user", token: session.accessToken)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(values)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await client.data(for: request)
        guard 200..<300 ~= response.statusCode else {
            throw APIError.httpStatus(
                response.statusCode,
                String(data: data, encoding: .utf8) ?? "Account konnte nicht aktualisiert werden"
            )
        }
    }

    private func refresh(_ token: String) async throws -> AuthSession {
        try await performSessionRequest(
            path: "token?grant_type=refresh_token",
            body: ["refresh_token": .string(token)]
        )
    }

    private func signInWithOAuth(provider: String) async throws -> AuthSession {
        let callbackScheme = "de.klangradar.native"
        let redirectURL = "\(callbackScheme)://login-callback"
        var components = URLComponents(
            url: configuration.supabaseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectURL)
        ]
        guard let authorizeURL = components.url else { throw AuthStoreError.unavailable }
        let callback = try await OAuthWebAuthentication.authenticate(url: authorizeURL, callbackScheme: callbackScheme)
        let values = Self.oauthValues(from: callback)
        if let message = values["error_description"] ?? values["error"] {
            throw APIError.httpStatus(400, message)
        }
        guard let accessToken = values["access_token"], let refreshToken = values["refresh_token"] else {
            throw APIError.httpStatus(400, "Der OAuth-Anbieter hat keine gueltige Sitzung zurueckgegeben.")
        }
        let expiresIn = Int(values["expires_in"] ?? "3600") ?? 3600

        var userRequest = authorizedRequest(path: "user", token: accessToken)
        userRequest.httpMethod = "GET"
        let (userData, response) = try await client.data(for: userRequest)
        guard 200..<300 ~= response.statusCode else {
            throw APIError.httpStatus(response.statusCode, String(data: userData, encoding: .utf8) ?? "Benutzerkonto konnte nicht geladen werden")
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

    private static func oauthValues(from url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        if let fragment = components?.fragment {
            items += URLComponents(string: "?\(fragment)")?.queryItems ?? []
        }
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
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
            let message = String(data: data, encoding: .utf8) ?? "Authentifizierung fehlgeschlagen"
            throw APIError.httpStatus(response.statusCode, message)
        }
        return data
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
