import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment

    @State private var selection: AppTab = .home
    // Ohne dieses @ObservedObject würde RootTabView.body nie neu ausgewertet,
    // wenn sich der Auth-Zustand ändert — .onChange(of: auth.userID) unten
    // bräuchte dafür eine body-Neuauswertung als Auslöser, die environment
    // als reines `let` sonst nicht liefert.
    @ObservedObject private var auth: AuthStore
    @StateObject private var favorites: FavoriteStore
    @StateObject private var follows: FollowStore
    @StateObject private var reportStore: ReportStore
    @StateObject private var genreFilterRouter = GenreFilterRouter()
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showsOnboarding = false
    @AppStorage("appearance") private var appearance = "system"

    init(environment: AppEnvironment) {
        self.environment = environment
        _auth = ObservedObject(wrappedValue: environment.auth)
        _favorites = StateObject(wrappedValue: FavoriteStore(auth: environment.auth, repository: environment.restClient.map(UserRepository.init(client:))))
        _follows = StateObject(wrappedValue: FollowStore(auth: environment.auth, repository: environment.restClient.map(UserRepository.init(client:))))
        _reportStore = StateObject(wrappedValue: ReportStore(auth: environment.auth, repository: environment.restClient.map(UserRepository.init(client:))))
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView(
                repository: environment.events,
                contentRepository: environment.content,
                usesPreviewData: environment.isUsingPreviewData,
                auth: environment.auth,
                userRepository: environment.restClient.map(UserRepository.init(client:))
            )
            .id(auth.userID)
            .tag(AppTab.home)
            .tabItem {
                Label("Home", systemImage: "house")
            }



            SearchView(
                eventRepository: environment.events,
                contentRepository: environment.content
            )
                .tag(AppTab.search)
                .tabItem {
                    Label("Suche", systemImage: "magnifyingglass")
                }

            VenueMapView(repository: environment.content, eventRepository: environment.events)
                .tag(AppTab.map)
                .tabItem {
                    Label("Karte", systemImage: "map")
                }

            EventCalendarView(
                repository: environment.events,
                contentRepository: environment.content,
                auth: environment.auth,
                userRepository: environment.restClient.map(UserRepository.init(client:))
            )
                .tag(AppTab.calendar)
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }

            ProfileView(
                usesPreviewData: environment.isUsingPreviewData,
                auth: environment.auth,
                userRepository: environment.restClient.map(UserRepository.init(client:)),
                editorialRepository: environment.restClient.map(EditorialRepository.init(client:)),
                eventRepository: environment.events,
                contentRepository: environment.content
            )
                .tag(AppTab.profile)
                .tabItem {
                    Label("Profil", systemImage: "person")
                }
        }
        .environmentObject(favorites)
        .environmentObject(follows)
        .environmentObject(reportStore)
        .environmentObject(genreFilterRouter)
        .onChange(of: genreFilterRouter.pending) { _, pending in
            if pending != nil { selection = .search }
        }
        .task {
            await auth.bootstrap()
            await refreshOnboardingGate()
        }
        .onChange(of: auth.userID) { _, _ in
            Task {
                await refreshOnboardingGate()
                await favorites.load()
                await follows.load()
            }
        }
        .task { await favorites.load() }
        .task { await follows.load() }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView(
                auth: auth,
                repository: environment.restClient.map(UserRepository.init(client:))
            ) {
                didCompleteOnboarding = true
                showsOnboarding = false
            }
        }
        .sheet(isPresented: $auth.isCompletingPasswordRecovery) {
            PasswordResetCompletionView(auth: auth)
        }
        .alert("Link konnte nicht geöffnet werden", isPresented: callbackErrorBinding) {
            Button("OK", role: .cancel) { auth.callbackErrorMessage = nil }
        } message: {
            Text(auth.callbackErrorMessage ?? "Bitte fordere einen neuen Link an.")
        }
        .onOpenURL { url in
            if url.scheme == AuthService.callbackScheme, url.host == "auth-callback" {
                showsOnboarding = false
                Task { await auth.handleAuthCallback(url) }
                return
            }
            let path = url.path.lowercased()
            if path.contains("search") { selection = .search }
            else if path.contains("map") || path.contains("venue") { selection = .map }
            else if path.contains("calendar") { selection = .calendar }
            else if path.contains("profile") || path.contains("admin") { selection = .profile }
            else { selection = .home }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var callbackErrorBinding: Binding<Bool> {
        Binding(
            get: { auth.callbackErrorMessage != nil },
            set: { if !$0 { auth.callbackErrorMessage = nil } }
        )
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    /// Zeigt das Onboarding, solange es lokal noch nie durchlaufen wurde
    /// (Gast-Skip zählt hier auch — "Ohne Account fortfahren" beendet den
    /// Flow), UND zusätzlich immer dann, wenn ein echter (nicht-anonymer)
    /// Account existiert, dessen `profiles.onboarding_completed` serverseitig
    /// noch nicht gesetzt ist — deckt Neuinstall/anderes Gerät mit
    /// bestehendem Account ab, ohne den lokalen Gast-Skip zu verlieren.
    private func refreshOnboardingGate() async {
        guard !auth.isCompletingPasswordRecovery else {
            showsOnboarding = false
            return
        }
        guard
            case .authenticated = auth.state,
            let userID = auth.userID,
            let token = auth.accessToken,
            let repository = environment.restClient.map(UserRepository.init(client:))
        else {
            showsOnboarding = !didCompleteOnboarding
            return
        }
        let completed = (try? await repository.isOnboardingCompleted(userID: userID, token: token)) ?? true
        // Ein bestehender Nutzer, der sich bewusst aus dem Profil anmeldet,
        // darf nicht zurück in den Registrierungsflow gezwungen werden. Das
        // serverseitige Flag hilft nur auf einer frischen Installation; ein
        // lokal bereits abgeschlossenes (auch als Gast übersprungenes)
        // Onboarding hat Vorrang.
        showsOnboarding = !didCompleteOnboarding && !completed
    }
}

private enum AppTab: Hashable {
    case home
    case search
    case map
    case calendar
    case profile
}
