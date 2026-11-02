import SwiftUI

// Navigation (02.11.2026, Nutzer: „man klickt auf etwas und nichts passiert,
// beim Zurück landet man dann erst auf der gewünschten Seite“). Ursache:
// Navigations-Stapel in Sheets/Panels (Freunde, Klangradar KI, Marketing-
// Start), in denen nur ein Teil der Ziele registriert war. Ein Tipp auf eine
// Person in einer dort geöffneten Konzertseite lief dann ins Leere.
// Jeder Stapel, der Konzerte oder Profile zeigen kann, registriert ab jetzt
// alle Ziele über diesen einen Baustein.
struct ContentNavigationDestinations: ViewModifier {
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(event: event, repository: eventRepository, contentRepository: contentRepository)
            }
            .navigationDestination(for: EntityRoute.self) { route in
                EntityDetailView(route: route, repository: contentRepository)
            }
            .navigationDestination(for: EntityKind.self) { kind in
                DirectoryView(kind: kind, repository: contentRepository)
            }
    }
}

extension View {
    func contentNavigationDestinations(events: any EventRepository, content: any ContentRepository) -> some View {
        modifier(ContentNavigationDestinations(eventRepository: events, contentRepository: content))
    }
}
