import AppIntents
import Foundation

/// Siri und Kurzbefehle. Die Sätze stehen in `KlangradarShortcuts` und
/// funktionieren ohne Einrichtung ("Hey Siri, nächstes Konzert in Klangradar").

/// Liest das nächste gemerkte Konzert aus dem App-Group-Speicher, den auch
/// das Widget nutzt. Kein Netz, kein App-Start nötig.
struct NextConcertIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächstes gemerktes Konzert"
    static let description = IntentDescription("Sagt dir, wann und wo dein nächstes gemerktes Konzert stattfindet.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = SharedConcertStore.load().first else {
            return .result(dialog: "Du hast gerade kein kommendes Konzert gemerkt.")
        }
        let date = KlangradarDateTime.string(next.start, format: "EEEE, d. MMMM 'um' HH:mm 'Uhr'")
        return .result(dialog: "\(next.title), \(date), \(next.venue).")
    }
}

/// Liest die nächsten drei gemerkten Konzerte vor (02.11.2026).
struct UpcomingConcertsIntent: AppIntent {
    static let title: LocalizedStringResource = "Meine nächsten Konzerte"
    static let description = IntentDescription("Liest deine nächsten drei gemerkten Konzerte vor.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let upcoming = SharedConcertStore.load().filter { $0.start > .now }.prefix(3)
        guard !upcoming.isEmpty else {
            return .result(dialog: "Du hast gerade keine kommenden Konzerte gemerkt.")
        }
        let lines = upcoming.map { concert in
            "\(KlangradarDateTime.string(concert.start, format: "EEEE, d. MMMM")): \(concert.title)"
        }
        return .result(dialog: "\(lines.joined(separator: ". ")).")
    }
}

/// „Wie lange noch?“ – Abstand bis zum nächsten gemerkten Konzert (02.11.2026).
struct ConcertCountdownIntent: AppIntent {
    static let title: LocalizedStringResource = "Wie lange bis zum nächsten Konzert"
    static let description = IntentDescription("Sagt dir, wie lange es noch bis zu deinem nächsten gemerkten Konzert dauert.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = SharedConcertStore.load().first(where: { $0.start > .now }) else {
            return .result(dialog: "Du hast gerade kein kommendes Konzert gemerkt.")
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: next.start)).day ?? 0
        let time = KlangradarDateTime.string(next.start, format: "HH:mm")
        let when: String = switch days {
        case 0: "heute um \(time) Uhr"
        case 1: "morgen um \(time) Uhr"
        default: "in \(days) Tagen"
        }
        return .result(dialog: "\(next.title) ist \(when), \(next.venue).")
    }
}

/// Spielstätte für Siri/Kurzbefehle (02.11.2026), gesucht über die
/// normale App-Suche – damit „Was läuft in der Isarphilharmonie?“ geht.
struct VenueEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Spielstätte")
    static let defaultQuery = VenueEntityQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct VenueEntityQuery: EntityStringQuery {
    @MainActor
    private func venues(matching text: String) async -> [VenueEntity] {
        let hits = (try? await AppEnvironment.make().content.search(query: text, limit: 30)) ?? []
        return hits.compactMap { hit in
            guard hit.kind == .venue, let slug = hit.slug else { return nil }
            return VenueEntity(id: slug, name: hit.title)
        }
    }

    func entities(matching string: String) async throws -> [VenueEntity] { await venues(matching: string) }
    func entities(for identifiers: [String]) async throws -> [VenueEntity] {
        identifiers.map { VenueEntity(id: $0, name: $0.replacingOccurrences(of: "-", with: " ").capitalized) }
    }
    func suggestedEntities() async throws -> [VenueEntity] {
        var result: [VenueEntity] = []
        for name in ["Isarphilharmonie", "Nationaltheater", "Herkulessaal", "Prinzregententheater", "Gärtnerplatztheater"] {
            if let first = await venues(matching: name).first { result.append(first) }
        }
        return result
    }
}

/// Öffnet die Seite einer Spielstätte mit ihren nächsten Konzerten.
struct VenueConcertsIntent: AppIntent {
    static let title: LocalizedStringResource = "Konzerte einer Spielstätte"
    static let description = IntentDescription("Zeigt, was demnächst in einer Spielstätte läuft.")
    static let openAppWhenRun = true

    @Parameter(title: "Spielstätte") var venue: VenueEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.pendingEntity = EntityRoute(kind: .venue, identifier: venue.id)
        return .result()
    }
}

/// Öffnet den Kalender (startet beim heutigen Tag).
struct TodayConcertsIntent: AppIntent {
    static let title: LocalizedStringResource = "Konzerte heute"
    static let description = IntentDescription("Öffnet den Klangradar-Kalender mit den heutigen Konzerten.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.pendingTab = "calendar"
        return .result()
    }
}

/// Öffnet die Klangradar KI.
struct AskKlangradarAIIntent: AppIntent {
    static let title: LocalizedStringResource = "Klangradar KI fragen"
    static let description = IntentDescription("Öffnet die Klangradar KI für Konzertempfehlungen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.pendingCoach = true
        return .result()
    }
}

struct KlangradarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextConcertIntent(),
            phrases: [
                "Nächstes Konzert in \(.applicationName)",
                "Wann ist mein nächstes Konzert in \(.applicationName)",
                "Mein nächstes Konzert mit \(.applicationName)"
            ],
            shortTitle: "Nächstes Konzert",
            systemImageName: "ticket"
        )
        AppShortcut(
            intent: VenueConcertsIntent(),
            phrases: [
                "Was läuft in \(\.$venue) in \(.applicationName)",
                "Konzerte in \(\.$venue) mit \(.applicationName)"
            ],
            shortTitle: "Spielstätte",
            systemImageName: "building.columns"
        )
        AppShortcut(
            intent: UpcomingConcertsIntent(),
            phrases: [
                "Meine nächsten Konzerte in \(.applicationName)",
                "Welche Konzerte habe ich in \(.applicationName)"
            ],
            shortTitle: "Nächste Konzerte",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: ConcertCountdownIntent(),
            phrases: [
                "Wie lange noch bis zum Konzert in \(.applicationName)",
                "Countdown bis zum Konzert in \(.applicationName)"
            ],
            shortTitle: "Countdown",
            systemImageName: "hourglass"
        )
        AppShortcut(
            intent: TodayConcertsIntent(),
            phrases: [
                "Was läuft heute in \(.applicationName)",
                "Konzerte heute in \(.applicationName)",
                "Zeig mir heutige Konzerte in \(.applicationName)"
            ],
            shortTitle: "Konzerte heute",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: AskKlangradarAIIntent(),
            phrases: [
                "\(.applicationName) KI fragen",
                "Frag die \(.applicationName) KI"
            ],
            shortTitle: "Klangradar KI",
            systemImageName: "sparkles"
        )
    }
}
