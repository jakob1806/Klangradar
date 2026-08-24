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
    @Published var isCompletingPasswordRecovery = false
    @Published var callbackErrorMessage: String?
    private let service: AuthService?
    private var operationGeneration = 0

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
        let generation = operationGeneration
        do {
            enabledOAuthProviders = (try? await service.enabledOAuthProviders()) ?? []
            let session = try await service.restoreOrCreateSession()
            guard generation == operationGeneration else { return }
            apply(session)
        } catch {
            guard generation == operationGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Legt den Account an. Ändert `state` bewusst NICHT — solange die
    /// E-Mail nicht per `verifySignupCode` bestätigt ist,
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

    func verifySignupCode(_ code: String, email: String) async throws {
        guard let service else { throw AuthStoreError.unavailable }
        apply(try await service.verifySignupCode(code, email: email))
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

    func handleAuthCallback(_ url: URL) async {
        guard url.scheme == AuthService.callbackScheme, url.host == "auth-callback", let service else { return }
        operationGeneration += 1
        callbackErrorMessage = nil
        do {
            let action = try await service.handleCallback(url)
            if let session = try? await service.restoreOrCreateSession() { apply(session) }
            isCompletingPasswordRecovery = action == .passwordRecovery
        } catch {
            callbackErrorMessage = error.localizedDescription
        }
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

enum AuthPasswordPolicy {
    static func requirements(for password: String) -> [(title: String, isMet: Bool)] {
        [
            ("Mindestens 8 Zeichen", password.count >= 8),
            ("Groß- und Kleinbuchstaben", password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase)),
            ("Mindestens eine Zahl", password.contains(where: \.isNumber))
        ]
    }

    static func isValid(_ password: String) -> Bool {
        requirements(for: password).allSatisfy(\.isMet)
    }
}
