// Erstellt von Claude Code (07.11.2026): Klangradar KI passt sich dem Bereich
// an, in dem man sich gerade befindet (Konzert, Person, Ensemble,
// Spielstätte, Werk, Startseite …) und schlägt passende Fragen vor.
import Foundation
import SwiftUI

struct CoachContext: Equatable, Sendable {
    enum Kind: String, Sendable { case home, event, person, ensemble, venue, work, search, calendar, profile }

    var kind: Kind
    var title: String? = nil
    /// Kurze Zusatzinfo, z. B. Datum und Ort eines Konzerts.
    var detail: String? = nil

    static let home = CoachContext(kind: .home)

    /// Erste Zeile im Chat, damit sichtbar ist, worauf sich die KI bezieht.
    var headline: String? {
        guard let title else { return nil }
        switch kind {
        case .event: return "Zum Konzert „\(title)“"
        case .person: return "Zu \(title)"
        case .ensemble: return "Zum Ensemble \(title)"
        case .venue: return "Zur Spielstätte \(title)"
        case .work: return "Zum Werk „\(title)“"
        default: return nil
        }
    }

    var suggestedPrompts: [String] {
        let name = title ?? ""
        switch kind {
        case .event:
            return ["Lohnt sich „\(name)“ für mich?", "Was wird gespielt und worauf achte ich?", "Ähnliche Konzerte in den nächsten Wochen", "Wann ist Pause, wann Schluss?"]
        case .person:
            return ["Wann tritt \(name) als Nächstes auf?", "Wofür ist \(name) bekannt?", "Wer klingt ähnlich wie \(name)?"]
        case .ensemble:
            return ["Kommende Konzerte von \(name)", "Was macht \(name) besonders?", "Welches Abo von \(name) passt zu mir?"]
        case .venue:
            return ["Was läuft demnächst im \(name)?", "Tipps für einen Abend im \(name)", "Wo sitzt man im \(name) am besten?"]
        case .work:
            return ["Erkläre „\(name)“ in drei Sätzen", "Wo kann ich „\(name)“ live hören?", "Welche Aufnahme sollte ich vorher hören?"]
        case .search:
            return ["Hilf mir, etwas Passendes zu finden", "Was ist diese Woche besonders?", "Etwas Neues für mich"]
        case .calendar:
            return ["Was passt in meine freien Abende?", "Plane meinen nächsten Monat", "Konzerte am Wochenende"]
        case .profile:
            return ["Erkläre mein Geschmacksprofil", "Was habe ich dieses Jahr gehört?", "Setz mir ein Hörziel"]
        case .home:
            return ["Was passt dieses Wochenende zu mir?", "Erkläre mein Geschmacksprofil", "Plane einen Abend unter 50 €", "Was läuft heute Abend?"]
        }
    }

    /// Persönliche Überschrift im Startbildschirm.
    var greeting: String {
        switch kind {
        case .event: return "Was willst du vor dem Abend wissen?"
        case .person: return "Was interessiert dich an \(title ?? "dieser Person")?"
        case .ensemble: return "Was möchtest du über \(title ?? "das Ensemble") wissen?"
        case .venue: return "Ein Abend im \(title ?? "Saal")?"
        case .work: return "Lass uns über dieses Werk reden."
        default: return "Worauf hast du Lust?"
        }
    }

    var symbol: String {
        switch kind {
        case .event: return "music.note"
        case .person: return "person.fill"
        case .ensemble: return "person.3.fill"
        case .venue: return "building.columns.fill"
        case .work: return "music.quarternote.3"
        default: return "sparkles"
        }
    }

    /// Rubrik über der Vorschlagskarte an Position `index`.
    func rubric(at index: Int) -> String {
        let rubrics: [String]
        switch kind {
        case .event: rubrics = ["Lohnt es sich?", "Vorbereiten", "Danach", "Der Abend"]
        case .person, .ensemble: rubrics = ["Live", "Hintergrund", "Entdecken", "Mehr"]
        case .venue: rubrics = ["Spielplan", "Der Abend", "Plätze", "Mehr"]
        case .work: rubrics = ["Kurz erklärt", "Live hören", "Vorhören", "Mehr"]
        default: rubrics = ["Für dich", "Geschmack", "Planen", "Heute"]
        }
        return rubrics[index % rubrics.count]
    }

    /// Unsichtbarer Hinweis für die KI (wird der Frage angehängt).
    var promptHint: String? {
        guard kind != .home, let title else { return nil }
        let place: String
        switch kind {
        case .event: place = "die Konzertseite"
        case .person: place = "die Seite der Person"
        case .ensemble: place = "die Seite des Ensembles"
        case .venue: place = "die Seite der Spielstätte"
        case .work: place = "die Seite des Werks"
        default: place = "den Bereich"
        }
        return "[Kontext: Ich schaue gerade auf \(place) „\(title)“\(detail.map { " (\($0))" } ?? "").]"
    }
}

@MainActor
final class CoachContextStore: ObservableObject {
    static let shared = CoachContextStore()
    @Published private(set) var current: CoachContext = .home
    private var stack: [CoachContext] = []

    func push(_ context: CoachContext) {
        stack.append(context)
        current = context
    }

    func pop(_ context: CoachContext) {
        if let index = stack.lastIndex(of: context) { stack.remove(at: index) }
        current = stack.last ?? .home
    }
}

extension View {
    /// Meldet den Bereich, solange die Ansicht sichtbar ist.
    func coachContext(_ context: CoachContext?) -> some View {
        modifier(CoachContextModifier(context: context))
    }
}

private struct CoachContextModifier: ViewModifier {
    let context: CoachContext?
    @State private var registered: CoachContext?

    func body(content: Content) -> some View {
        content
            .onAppear { register(context) }
            .onChange(of: context) { _, new in register(new) }
            .onDisappear { if let registered { CoachContextStore.shared.pop(registered); self.registered = nil } }
    }

    private func register(_ new: CoachContext?) {
        if let registered { CoachContextStore.shared.pop(registered) }
        registered = new
        if let new { CoachContextStore.shared.push(new) }
    }
}
