import XCTest
@testable import KlangradarNative

/// Regression: Ein vom Server abgelehnter Refresh-Token ("Refresh Token Not
/// Found") blieb dauerhaft in der Keychain, die App zeigte im Profil nur noch
/// den Fehler und die Anmeldung war blockiert.
final class AuthSessionRestoreTests: XCTestCase {
    private final class MockClient: HTTPClient, @unchecked Sendable {
        private(set) var paths: [String] = []
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!
            paths.append(url.path + (url.query.map { "?\($0)" } ?? ""))
            if url.query?.contains("grant_type=refresh_token") == true {
                let body = #"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token: Refresh Token Not Found"}"#
                return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!)
            }
            let body = #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"bearer","user":{"id":"00000000-0000-0000-0000-000000000001","is_anonymous":true}}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testRejectedRefreshTokenFallsBackToFreshSession() async throws {
        let keychain = KeychainStore(memory: .init())
        let expired = #"{"access_token":"old","refresh_token":"dead","expires_in":3600,"expires_at":1000,"token_type":"bearer","user":{"id":"00000000-0000-0000-0000-000000000002","is_anonymous":false}}"#
        try keychain.save(Data(expired.utf8), account: "supabase-session")
        defer { try? keychain.delete(account: "supabase-session") }

        let client = MockClient()
        let service = AuthService(
            configuration: APIConfiguration(supabaseURL: URL(string: "https://example.supabase.co")!, supabaseAnonKey: "anon"),
            client: client,
            keychain: keychain
        )
        let session = try await service.restoreOrCreateSession()
        XCTAssertEqual(session.accessToken, "new-access")
        XCTAssertEqual(client.paths.count, 2, "erst Refresh (abgelehnt), dann neue anonyme Session")
    }
}
