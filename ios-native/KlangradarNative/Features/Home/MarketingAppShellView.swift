import SwiftUI

/// Eigenständige Tab-Leiste für Marketing-Screenshots: „Home" zeigt den frei
/// editierbaren Homescreen-Nachbau (`MarketingHomeScreenView`), die übrigen
/// vier Tabs sind exakt dieselben Live-Screens wie in `RootTabView` — echte
/// Daten, echtes Redaktionsmodus-Editing für Personen/Ensembles/Venues und
/// Veranstaltungen über die vorhandene Suche/Karte/Kalender-Navigation.
/// Als eigene `TabView`, per `.fullScreenCover` präsentiert (statt per
/// `NavigationLink` aus Profil heraus), damit die Tab-Leiste unten wirklich
/// „Home" statt „Profil" als aktiv zeigt — für authentische Screenshots.
/// Nur in Debug-Builds erreichbar (siehe ProfileView).
struct MarketingAppShellView: View {
    let auth: AuthStore
    let userRepository: UserRepository?
    let editorialRepository: EditorialRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    let usesPreviewData: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selection: MarketingTab = .home
    // Von SearchView/EventCard/EntityDetailView usw. per @EnvironmentObject
    // erwartet — dieselben Stores wie in RootTabView, sonst crasht das
    // Öffnen der Live-Tabs mangels ObservableObject im Environment.
    @StateObject private var favorites: FavoriteStore
    @StateObject private var follows: FollowStore
    @StateObject private var reportStore: ReportStore
    @StateObject private var cityStore: CityStore
    @StateObject private var genreFilterRouter = GenreFilterRouter()

    init(
        auth: AuthStore,
        userRepository: UserRepository?,
        editorialRepository: EditorialRepository?,
        eventRepository: any EventRepository,
        contentRepository: any ContentRepository,
        usesPreviewData: Bool
    ) {
        self.auth = auth
        self.userRepository = userRepository
        self.editorialRepository = editorialRepository
        self.eventRepository = eventRepository
        self.contentRepository = contentRepository
        self.usesPreviewData = usesPreviewData
        _favorites = StateObject(wrappedValue: FavoriteStore(auth: auth, repository: userRepository))
        _follows = StateObject(wrappedValue: FollowStore(auth: auth, repository: userRepository))
        _reportStore = StateObject(wrappedValue: ReportStore(auth: auth, repository: userRepository))
        _cityStore = StateObject(wrappedValue: CityStore(auth: auth, repository: userRepository))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selection) {
                MarketingHomeScreenView()
                    .tag(MarketingTab.home)
                    .tabItem { Label("Home", systemImage: "house") }

                SearchView(eventRepository: eventRepository, contentRepository: contentRepository)
                    .tag(MarketingTab.search)
                    .tabItem { Label("Suche", systemImage: "magnifyingglass") }

                VenueMapView(repository: contentRepository, eventRepository: eventRepository, cityStore: cityStore)
                    .tag(MarketingTab.map)
                    .tabItem { Label("Karte", systemImage: "map") }

                EventCalendarView(
                    repository: eventRepository,
                    contentRepository: contentRepository,
                    auth: auth,
                    userRepository: userRepository
                )
                    .tag(MarketingTab.calendar)
                    .tabItem { Label("Kalender", systemImage: "calendar") }

                ProfileView(
                    usesPreviewData: usesPreviewData,
                    auth: auth,
                    userRepository: userRepository,
                    editorialRepository: editorialRepository,
                    eventRepository: eventRepository,
                    contentRepository: contentRepository
                )
                    .tag(MarketingTab.profile)
                    .tabItem { Label("Profil", systemImage: "person") }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.secondary, Color(.systemBackground).opacity(0.85))
            }
            .padding(12)
            .accessibilityLabel("Marketing-Vorschau schließen")
        }
        .environmentObject(favorites)
        .environmentObject(follows)
        .environmentObject(reportStore)
        .environmentObject(genreFilterRouter)
        .environmentObject(cityStore)
        .task { await favorites.load() }
        .task { await follows.load() }
        .task { await cityStore.load() }
    }
}

private enum MarketingTab: Hashable {
    case home, search, map, calendar, profile
}
