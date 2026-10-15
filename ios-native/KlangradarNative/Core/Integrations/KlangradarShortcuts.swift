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
