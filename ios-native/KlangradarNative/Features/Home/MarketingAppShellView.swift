import SwiftUI
import UIKit

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
    @State private var eventsLoadError: String?
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
                preparationBar
            } else {
                MarketingHomeTabDoubleTapObserver { dismiss() }
                    .allowsHitTesting(false)
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
        eventsLoadError = nil
        do {
            let events = try await eventRepository.allUpcomingEvents()
            availableEvents = (try? await eventRepository.enrichingImages(in: events)) ?? events
        } catch {
            eventsLoadError = "Echte Veranstaltungen konnten nicht geladen werden."
        }
    }

    private var preparationBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Button(role: .cancel) { dismiss() } label: {
                    Label("Schließen", systemImage: "xmark")
                }
                .buttonStyle(.bordered)

                Spacer()

                if let eventsLoadError {
                    Text(eventsLoadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button {
                    isPresentationMode = true
                } label: {
                    Label("Fertig", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
            .padding(.horizontal, 14)
            .padding(.bottom, 58)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}

private enum MarketingTab: Hashable {
    case home, search, map, calendar, profile
}

/// Beobachtet einen Doppeltipp auf das echte Home-Tab-Bar-Element, ohne
/// dessen normale Einzeltipp-Navigation zu blockieren. Ein transparentes
/// SwiftUI-Overlay würde den Home-Tab sonst unbedienbar machen.
private struct MarketingHomeTabDoubleTapObserver: UIViewControllerRepresentable {
    let onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDoubleTap: onDoubleTap) }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attach(from: controller) }
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onDoubleTap = onDoubleTap
        DispatchQueue.main.async { context.coordinator.attach(from: controller) }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDoubleTap: () -> Void
        private weak var tabBar: UITabBar?
        private var recognizer: UITapGestureRecognizer?

        init(onDoubleTap: @escaping () -> Void) { self.onDoubleTap = onDoubleTap }

        func attach(from controller: UIViewController) {
            guard let tabBar = controller.tabBarController?.tabBar, self.tabBar !== tabBar else { return }
            if let recognizer, let oldTabBar = self.tabBar { oldTabBar.removeGestureRecognizer(recognizer) }
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            tabBar.addGestureRecognizer(recognizer)
            self.tabBar = tabBar
            self.recognizer = recognizer
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let tabBar, let itemCount = tabBar.items?.count, itemCount > 0 else { return false }
            let location = touch.location(in: tabBar)
            return location.x >= 0 && location.x <= tabBar.bounds.width / CGFloat(itemCount)
        }

        @objc private func didDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onDoubleTap()
        }
    }
}
