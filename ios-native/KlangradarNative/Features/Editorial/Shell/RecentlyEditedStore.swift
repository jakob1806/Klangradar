import Foundation

struct RecentlyEditedItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case event, venue, person, ensemble, work

        var title: String {
            switch self {
            case .event: "Veranstaltung"
            case .venue: "Venue"
            case .person: "Person"
            case .ensemble: "Ensemble"
            case .work: "Werk"
            }
        }

        var entityKind: EditorialEntityKind? {
            switch self {
            case .event: nil
            case .venue: .venue
            case .person: .person
            case .ensemble: .ensemble
            case .work: .work
            }
        }

        init(_ kind: EditorialEntityKind) {
            switch kind {
            case .venue: self = .venue
            case .person: self = .person
            case .ensemble: self = .ensemble
            case .work: self = .work
            }
        }
    }

    let id: UUID
    let kind: Kind
    let title: String
    let timestamp: Date
}

/// Punkt 2 des Redesigns, "zuletzt bearbeitet" — rein lokal (UserDefaults),
/// bewusst ohne Backend-Feld: eine "zuletzt von mir bearbeitet"-Historie ist
/// geräte-/editor-lokal und würde sonst ein neues Server-Feld erfordern
/// (CLAUDE.md-Regel 5: keine Ersatz-Backend-Felder erfinden).
@MainActor
final class RecentlyEditedStore: ObservableObject {
    static let shared = RecentlyEditedStore()

    private static let storageKey = "editorial.recentlyEdited"
    private static let limit = 15

    @Published private(set) var items: [RecentlyEditedItem] = []

    private init() {
        items = Self.load()
    }

    func record(kind: RecentlyEditedItem.Kind, id: UUID, title: String) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var updated = items.filter { !($0.kind == kind && $0.id == id) }
        updated.insert(RecentlyEditedItem(id: id, kind: kind, title: title, timestamp: Date()), at: 0)
        items = Array(updated.prefix(Self.limit))
        Self.save(items)
    }

    private static func load() -> [RecentlyEditedItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RecentlyEditedItem].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ items: [RecentlyEditedItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
