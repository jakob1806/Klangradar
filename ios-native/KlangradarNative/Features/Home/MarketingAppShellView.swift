import SwiftUI

/// Eigenständige Tab-Leiste für Marketing-Screenshots: „Home" und „Suche"
/// zeigen die frei editierbaren Nachbauten (`MarketingHomeScreenView`,
/// `MarketingSearchScreenView`), die übrigen drei Tabs sind exakt dieselben
/// Live-Screens wie in `RootTabView` — überall normale Navigation, auch auf
/// einzelne Veranstaltungen. Als eigene `TabView`, per `.fullScreenCover`
/// präsentiert (statt per `NavigationLink` aus Profil heraus), damit die
/// Tab-Leiste unten wirklich „Home" statt „Profil" als aktiv zeigt — für
/// authentische Screenshots. Nur in Debug-Builds erreichbar (siehe
/// ProfileView).
///
/// Ein einziger Modus statt zweier getrennter Einstiege: die Ansicht startet
/// bearbeitbar (Stift in Home/Suche sichtbar, X oben links zum Abbrechen).
/// „Fertig" im Bearbeiten-Sheet blendet beides aus — ab dann ist die
/// Oberfläche unverändert aufnahmebereit. Heraus kommt man nur noch per
/// Doppeltipp auf den Home-Tab, damit eine Aufnahme nie versehentlich das
/// Werkzeug zeigt.
struct MarketingAppShellView: View {
    let auth: AuthStore
    let userRepository: UserRepository?
    let editorialRepository: EditorialRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    let usesPreviewData: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selection: MarketingTab = .home
    @State private var isPresentationMode = false
    @State private var availableEvents: [ConcertEvent] = []
    @StateObject private var marketingContent = MarketingContentStore()
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
                MarketingHomeScreenView(
                    isPresentationMode: $isPresentationMode,
                    availableEvents: availableEvents,
                    eventRepository: eventRepository,
                    contentRepository: contentRepository
                )
                    .tag(MarketingTab.home)
                    .tabItem { Label("Home", systemImage: "house") }

                MarketingSearchScreenView(
                    isPresentationMode: $isPresentationMode,
                    availableEvents: availableEvents,
                    eventRepository: eventRepository,
                    contentRepository: contentRepository
                )
                    .tag(MarketingTab.search)
                    .tabItem { Label("Suche", systemImage: "magnifyingglass") }

                VenueMapView(repository: contentRepository, eventRepository: eventRepository, cityStore: cityStore)
                    .tag(MarketingTab.map)
                    .tabItem { Label("Karte", systemImage: "map") }

                EventCalendarView(
                    repository: eventRepository,
                    contentRepository: contentRepository,
                    auth: auth,
                    userRepository: userRepository,
                    hidesSelectionUI: true
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

            if !isPresentationMode {
                // Nutzerfeedback: das X lag oben rechts genau über dem
                // "Bearbeiten"-Stift der Live-Tabs (Home/Suche-Toolbar,
                // ebenfalls top-trailing) und verdeckte ihn. Bewusst links
                // statt rechts, damit beide Werkzeuge während des
                // Vorbereitens gleichzeitig erreichbar bleiben.
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.secondary, Color(.systemBackground).opacity(0.85))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Marketing-Vorschau schließen")
            }

            // Im fertigen Aufnahmezustand bleibt die gesamte Oberfläche frei
            // von Werkzeugen. Ein bewusster Doppeltipp auf Home ist der
            // einzige Ausstieg und wird nicht versehentlich in einer Aufnahme
            // ausgelöst.
            if isPresentationMode {
                VStack {
                    Spacer()
                    HStack {
                        Color.clear
                            .frame(width: 88, height: 54)
                            .contentShape(.rect)
                            .onTapGesture(count: 2) { dismiss() }
                        Spacer()
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("Marketing-Vorschau per Doppeltipp auf Home schließen")
            }
        }
        .environmentObject(favorites)
        .environmentObject(follows)
        .environmentObject(reportStore)
        .environmentObject(genreFilterRouter)
        .environmentObject(cityStore)
        .environmentObject(marketingContent)
        .task { await favorites.load() }
        .task { await follows.load() }
        .task { await cityStore.load() }
        .task { await loadAvailableEvents() }
    }

    // Nutzerfeedback: "man kann nicht alle Konzerte unter 'Echtes Event
    // auswählen' auswählen" -- upcomingEvents(limit: 150) deckelte die Liste
    // auf die ersten 150 chronologisch nächsten Termine über alle Städte
    // hinweg; alles Weitere in der Zukunft fehlte im Picker komplett.
    // allUpcomingEvents() paginiert stattdessen durch den vollständigen
    // Bestand -- vertretbar hier, weil der Bereich nur in der
    // Redaktions-Vorschau geladen wird, nicht im echten Nutzerfluss.
    @MainActor
    private func loadAvailableEvents() async {
        guard let events = try? await eventRepository.allUpcomingEvents() else { return }
        availableEvents = (try? await eventRepository.enrichingImages(in: events)) ?? events
    }
}

private enum MarketingTab: Hashable {
    case home, search, map, calendar, profile
}
