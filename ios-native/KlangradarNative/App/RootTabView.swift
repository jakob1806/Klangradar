import SwiftUI

struct RootTabView: View {
    let environment: AppEnvironment

    @State private var selection: AppTab = .home
    @StateObject private var favorites: FavoriteStore
    @StateObject private var follows: FollowStore
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var showsOnboarding = false
    @AppStorage("appearance") private var appearance = "system"

    init(environment: AppEnvironment) {
        self.environment = environment
        _favorites = StateObject(wrappedValue: FavoriteStore(auth: environment.auth, repository: environment.restClient.map(UserRepository.init(client:))))
        _follows = StateObject(wrappedValue: FollowStore(auth: environment.auth, repository: environment.restClient.map(UserRepository.init(client:))))
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
        .task { await environment.auth.bootstrap(); showsOnboarding = !didCompleteOnboarding }
        .task { await favorites.load() }
        .task { await follows.load() }
        .fullScreenCover(isPresented: $showsOnboarding) { OnboardingView() }
        .onOpenURL { url in
            let path = url.path.lowercased()
            if path.contains("search") { selection = .search }
            else if path.contains("map") || path.contains("venue") { selection = .map }
            else if path.contains("calendar") { selection = .calendar }
            else if path.contains("profile") || path.contains("admin") { selection = .profile }
            else { selection = .home }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
}

private enum AppTab: Hashable {
    case home
    case search
    case map
    case calendar
    case profile
}
