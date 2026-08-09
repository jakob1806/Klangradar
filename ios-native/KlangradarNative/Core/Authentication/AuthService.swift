import Foundation

actor AuthService {
    private let configuration: APIConfiguration
    private let client: any HTTPClient
    private let keychain: KeychainStore
    private let sessionAccount = "supabase-session"
    private var cachedSession: AuthSession?

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
            return try await refresh(session.refreshToken)
        }

        return try await signInAnonymously()
    }

    func signInAnonymously() async throws -> AuthSession {
        try await performSessionRequest(path: "signup", body: ["data": .object([:])])
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

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthSession {
        try await performSessionRequest(
            path: "verify",
            body: [
                "email": .string(email),
                "token": .string(code),
                "type": .string("email")
            ]
        )
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

    private func refresh(_ token: String) async throws -> AuthSession {
        try await performSessionRequest(
            path: "token?grant_type=refresh_token",
            body: ["refresh_token": .string(token)]
        )
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

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
