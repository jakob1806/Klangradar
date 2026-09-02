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
        case verifyEmail(email: String, marketingEmailOptIn: Bool)
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
                auth: auth,
                onCreateAccount: { path.append(.signUp) },
                onLogIn: { showsLogin = true },
                onContinueAsGuest: { onFinished() },
                onAuthenticated: onFinished
            )
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .signUp:
                    SignUpStepView(auth: auth) { email, marketingEmailOptIn in
                        path.append(.verifyEmail(email: email, marketingEmailOptIn: marketingEmailOptIn))
                    }
                case let .verifyEmail(email, marketingEmailOptIn):
                    VerifyEmailStepView(
                        auth: auth,
                        repository: repository,
                        email: email,
                        marketingEmailOptIn: marketingEmailOptIn
                    ) {
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
                    CityPickerStepView(auth: auth, repository: repository) {
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
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let currentProgressStep {
                OnboardingProgressHeader(current: currentProgressStep, total: 6)
            }
        }
        .sheet(isPresented: $showsLogin) {
            PasswordLoginView(
                auth: auth,
                repository: repository,
                onSignedIn: onFinished,
                onCreatedAccount: {
                    showsLogin = false
                    path = [.personalData]
                }
            )
        }
        .interactiveDismissDisabled()
    }

    private var currentProgressStep: Int? {
        switch path.last {
        case .signUp: 1
        case .verifyEmail: 2
        case .personalData: 3
        case .interests: 4
        case .location: 5
        case .notifications, .summary: 6
        case nil: nil
        }
    }

    private func finish() async {
        if case .authenticated = auth.state, let userID = auth.userID, let token = auth.accessToken {
            try? await repository?.markOnboardingCompleted(userID: userID, token: token)
        }
        onFinished()
    }
}
