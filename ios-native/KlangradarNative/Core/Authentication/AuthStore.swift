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
    @Published private(set) var enabledOAuthProviders: Set<String> = []
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
    var isGoogleSignInAvailable: Bool { enabledOAuthProviders.contains("google") }
    var isAppleSignInAvailable: Bool { enabledOAuthProviders.contains("apple") }

    func bootstrap() async {
        guard let service else { return }
        do {
            enabledOAuthProviders = (try? await service.enabledOAuthProviders()) ?? []
            apply(try await service.restoreOrCreateSession())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func sendEmailCode(to email: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.sendEmailCode(to: email)
    }

    /// Legt den Account an. Ändert `state` bewusst NICHT — solange die
    /// E-Mail nicht per `verifyEmailCode(type: "signup")` bestätigt ist,
    /// gibt es keine Session, der Nutzer bleibt in der aktuellen (meist
    /// anonymen) Bootstrap-Session.
    func signUp(email: String, password: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        _ = try await service.signUp(email: email, password: password)
    }

    func signInWithPassword(email: String, password: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        apply(try await service.signInWithPassword(email: email, password: password))
    }

    func requestPasswordReset(email: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.requestPasswordReset(email: email)
    }

    func resendSignupConfirmation(email: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.resendSignupConfirmation(email: email)
    }

    func verifyEmailCode(_ code: String, email: String, type: String = "email") async throws {
        guard let service else { throw AuthStoreError.unavailable }
        apply(try await service.verifyEmailCode(code, email: email, type: type))
    }

    func signInWithGoogle() async throws {
        guard let service else { throw AuthStoreError.unavailable }
        apply(try await service.signInWithGoogle())
    }

    func signInWithApple() async throws {
        guard let service else { throw AuthStoreError.unavailable }
        apply(try await service.signInWithApple())
    }

    func signOut() async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.signOut()
        state = .loading
        apply(try await service.signInAnonymously())
    }

    func updateEmail(_ email: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.updateEmail(email)
    }

    func updatePassword(_ password: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        try await service.updatePassword(password)
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
