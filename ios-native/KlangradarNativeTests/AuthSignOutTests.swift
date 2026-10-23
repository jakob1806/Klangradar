import XCTest
@testable import KlangradarNative

/// Regression (23.10.2026): Nach dem Abmelden blieb die App dauerhaft bei
/// "Sitzung wird vorbereitet", wenn die neue anonyme Sitzung scheiterte
/// (z. B. Supabase-Limit für anonyme Anmeldungen). Erwartet: .failed statt .loading.
@MainActor
final class AuthSignOutTests: XCTestCase {
    private final class FailingAnonymousClient: HTTPClient, @unchecked Sendable {
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let url = request.url!
            if url.path.hasSuffix("/logout") {
                return (Data(), HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!)
            }
            let body = #"{"code":429,"error_code":"over_request_rate_limit","msg":"Request rate limit reached"}"#
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testSignOutWithFailingAnonymousSessionDoesNotHang() async throws {
        let keychain = KeychainStore(memory: .init())
        let service = AuthService(
            configuration: APIConfiguration(supabaseURL: URL(string: "https://example.supabase.co")!, supabaseAnonKey: "anon"),
            client: FailingAnonymousClient(),
            keychain: keychain
        )
        let store = AuthStore(service: service)
        try? await store.signOut()
        guard case .failed = store.state else {
            return XCTFail("erwartet .failed, war \(store.state)")
        }
    }
}
