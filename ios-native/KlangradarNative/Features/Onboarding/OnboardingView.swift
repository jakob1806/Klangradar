import SwiftUI

/// Koordiniert den gesamten Onboarding-Ablauf: Einstieg (Anmelden/Account
/// erstellen/Gast) → Account erstellen → E-Mail bestätigen → Persönliche
/// Daten → Interessen → Standort → Benachrichtigungen → Zusammenfassung.
/// "Account erstellen" ist verpflichtend, sobald gewählt — nur der
/// Einstiegs-Schritt selbst lässt sich mit "Ohne Account fortfahren"
/// überspringen (anonyme Bootstrap-Session bleibt aktiv). `onFinished` wird
/// von RootTabView übergeben und kümmert sich dort um das lokale
/// "didCompleteOnboarding"-Flag und das Schließen des FullScreenCovers.
struct OnboardingView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onFinished: () -> Void

    private enum Step: Hashable {
        case signUp
        case verifyEmail(email: String)
        case personalData
        case interests
        case location
        case notifications
        case summary
    }

    @State private var path: [Step] = []
    @State private var showsLogin = false

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStepView(
                onCreateAccount: { path.append(.signUp) },
                onLogIn: { showsLogin = true },
                onContinueAsGuest: { onFinished() }
            )
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .signUp:
                    SignUpStepView(auth: auth) { email in
                        path.append(.verifyEmail(email: email))
                    }
                case let .verifyEmail(email):
                    VerifyEmailStepView(auth: auth, repository: repository, email: email) {
                        path.append(.personalData)
                    }
                case .personalData:
                    PersonalDataStepView(auth: auth, repository: repository) {
                        path.append(.interests)
                    }
                case .interests:
                    InterestsStepView(auth: auth, repository: repository) {
                        path.append(.location)
                    }
                case .location:
                    LocationStepView(auth: auth, repository: repository) {
                        path.append(.notifications)
                    }
                case .notifications:
                    NotificationsStepView(auth: auth, repository: repository) {
                        path.append(.summary)
                    }
                case .summary:
                    OnboardingSummaryView(auth: auth, repository: repository) {
                        Task { await finish() }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showsLogin) {
            PasswordLoginView(auth: auth) { onFinished() }
        }
        .interactiveDismissDisabled()
    }

    private func finish() async {
        if case .authenticated = auth.state, let userID = auth.userID, let token = auth.accessToken {
            try? await repository?.markOnboardingCompleted(userID: userID, token: token)
        }
        onFinished()
    }
}
