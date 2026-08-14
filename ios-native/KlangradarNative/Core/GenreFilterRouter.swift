import Foundation

/// Nutzeranfrage: Genre-Chips in der Veranstaltungsdetailansicht sollen
/// antippbar sein und zu den passenden Veranstaltungen führen (Parität zur
/// Flutter-App, die dafür `eventFiltersProvider` + `context.go('/search')`
/// nutzt, siehe app/lib/features/event_detail/presentation/
/// event_detail_screen.dart). Da Tabs in der nativen App unabhängige
/// NavigationStacks besitzen, reicht ein lokaler State in EventDetailView
/// nicht — dieses als @EnvironmentObject injizierte Objekt trägt die Anfrage
/// über den Tab-Wechsel hinweg zur Suche.
@MainActor
final class GenreFilterRouter: ObservableObject {
    struct Genre: Equatable {
        let id: UUID
        let label: String
    }

    @Published var pending: Genre?

    func request(id: UUID, label: String) {
        pending = Genre(id: id, label: label)
    }

    func consume() -> Genre? {
        defer { pending = nil }
        return pending
    }
}
