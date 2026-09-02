import SwiftUI

/// Koordiniert den gesamten Onboarding-Ablauf: Einstieg (Anmelden/Account
/// erstellen/Gast) → Account erstellen → E-Mail bestätigen → Persönliche
/// Daten → Interessen → Stadt → Personen/Ensembles/Venues folgen →
/// Benachrichtigungen → Zusammenfassung.
/// "Account erstellen" ist verpflichtend, sobald gewählt — nur der
/// Einstiegs-Schritt selbst lässt sich mit "Ohne Account fortfahren"
/// überspringen (anonyme Bootstrap-Session bleibt aktiv). `onFinished` wird
/// von RootTabView übergeben und kümmert sich dort um das lokale
/// "didCompleteOnboarding"-Flag und das Schließen des FullScreenCovers.
struct OnboardingView: View {
    /// Erlaubt Aufrufern (z.B. "Anmelden" im Profil), direkt beim Login-
    /// Formular bzw. beim Sign-up-Schritt einzusteigen statt beim
    /// Willkommens-Bildschirm — der Rest des Flows (inkl. aller Folgeschritte
    /// bei Kontoerstellung) bleibt derselbe wie beim regulären Einstieg.
    enum InitialAction {
        case login
        case signUp
    }

    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    var initialAction: InitialAction? = nil
    let onFinished: () -> Void

    private enum Step: Hashable {
        case signUp
        case verifyEmail(email: String, marketingEmailOptIn: Bool)
        case personalData
        case interests
        case location
        case followProfiles
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
                        path.append(.followProfiles)
                    }
                case .followProfiles:
                    FollowProfilesStepView(auth: auth, repository: repository) {
                        path.append(.notifications)
                    }
                case .notifications:
                    NotificationsStepView(auth: auth, repository: repository) {
                        path.append(.summary)
                    }
                case .summary:
                    OnboardingSummaryView(
                        auth: auth,
                        repository: repository,
                        onEditCity: { editStep(matching: { if case .location = $0 { true } else { false } }) },
                        onEditFollows: { editStep(matching: { if case .followProfiles = $0 { true } else { false } }) },
                        onEditNotifications: { editStep(matching: { if case .notifications = $0 { true } else { false } }) }
                    ) {
                        Task { await finish() }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let currentProgressStep {
                OnboardingProgressHeader(
                    current: currentProgressStep,
                    total: 7,
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
            }
        }
        .sheet(isPresented: $showsLogin) {
            PasswordLoginView(
                auth: auth,
                repository: repository,
                onSignedIn: onFinished,
                onRequestSignUp: {
                    showsLogin = false
                    path = [.signUp]
                }
            )
        }
        .interactiveDismissDisabled()
        .task {
            switch initialAction {
            case .login: showsLogin = true
            case .signUp: path = [.signUp]
            case nil: break
            }
        }
    }

    private var currentProgressStep: Int? {
        switch path.last {
        case .signUp: 1
        case .verifyEmail: 2
        case .personalData: 3
        case .interests: 4
        case .location: 5
        case .followProfiles: 6
        case .notifications, .summary: 7
        case nil: nil
        }
    }

    /// Springt aus der Zusammenfassung zurück zu einem bereits durchlaufenen
    /// Schritt (z.B. "Bearbeiten" bei Stadt/Folgen/Benachrichtigungen) --
    /// entfernt alles NACH diesem Schritt aus dem Pfad, statt ihn erneut
    /// anzuhängen, damit "Weiter" von dort aus nicht zu doppelten Einträgen
    /// im Stack führt.
    private func editStep(matching predicate: (Step) -> Bool) {
        guard let index = path.firstIndex(where: predicate), index + 1 < path.count else { return }
        path.removeSubrange((index + 1)...)
    }

    private func finish() async {
        if case .authenticated = auth.state, let userID = auth.userID, let token = auth.accessToken {
            try? await repository?.markOnboardingCompleted(userID: userID, token: token)
        }
        onFinished()
    }
}
