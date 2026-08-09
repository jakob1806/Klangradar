import Foundation

@MainActor
final class AuthStore: ObservableObject {
    enum State {
        case unavailable
        case loading
        case anonymous(AuthSession)
        case authenticated(AuthSession)
        case failed(String)
    }

    @Published private(set) var state: State
    private let service: AuthService?

    init(service: AuthService?) {
        self.service = service
        self.state = service == nil ? .unavailable : .loading
    }

    var session: AuthSession? {
        switch state {
        case let .anonymous(session), let .authenticated(session): session
        default: nil
        }
    }

    var accessToken: String? { session?.accessToken }
    var userID: UUID? { session?.user.id }

    func bootstrap() async {
        guard let service else { return }
        do {
            apply(try await service.restoreOrCreateSession())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func sendEmailCode(to email: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.sendEmailCode(to: email)
    }

    func verifyEmailCode(_ code: String, email: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        apply(try await service.verifyEmailCode(code, email: email))
    }

    func signOut() async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.signOut()
        state = .loading
        apply(try await service.signInAnonymously())
    }

    private func apply(_ session: AuthSession) {
        state = session.user.isAnonymous == true
            ? .anonymous(session)
            : .authenticated(session)
    }
}

enum AuthStoreError: Error {
    case unavailable
}
