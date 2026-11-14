// Erstellt von Claude Code (14.11.2026): prüft beim Ticket-Hinzufügen, ob
// Datum, Ort und Titel auf dem Ticket zum gewählten Konzert passen.
// Fehlt eine Angabe auf dem Ticket, gilt sie nicht als Widerspruch –
// gewarnt wird nur bei klaren Abweichungen.
import Foundation

struct TicketMatch: Equatable, Sendable {
    enum State: Equatable, Sendable { case matches, differs, unknown }
    var date: State = .unknown
    var venue: State = .unknown
    var title: State = .unknown
    /// Auf dem Ticket gefundenes Datum (falls abweichend), z. B. „12.12.2026“.
    var ticketDate: String?

    /// Klare Abweichung: anderes Datum, oder weder Ort noch Titel gefunden.
    var isSuspicious: Bool {
        date == .differs || (venue == .differs && title == .differs)
    }

    var message: String {
        var parts: [String] = []
        if date == .differs { parts.append(ticketDate.map { "Auf dem Ticket steht der \($0)." } ?? "Das Datum auf dem Ticket ist ein anderes.") }
        if venue == .differs { parts.append("Der Ort wurde auf dem Ticket nicht gefunden.") }
        if title == .differs { parts.append("Der Konzerttitel wurde auf dem Ticket nicht gefunden.") }
        return parts.joined(separator: " ")
    }

    static func check(text: String, title: String, venue: String?, start: Date?) -> TicketMatch {
        let hay = normalize(text)
        guard hay.count > 20 else { return TicketMatch() }
        var result = TicketMatch()

        // Datum
        if let start {
            let found = dates(in: text)
            if !found.isEmpty {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
                let target = calendar.dateComponents([.year, .month, .day], from: start)
                if found.contains(where: { $0.day == target.day && $0.month == target.month && ($0.year == nil || $0.year == target.year) }) {
                    result.date = .matches
                } else {
                    result.date = .differs
                    if let first = found.first {
                        result.ticketDate = String(format: "%02d.%02d.%@", first.day, first.month, first.year.map(String.init) ?? "")
                    }
                }
            }
        }

        // Ort: ein markantes Wort aus dem Spielstättennamen genügt.
        if let venue {
            let tokens = significant(venue)
            if !tokens.isEmpty { result.venue = tokens.contains(where: hay.contains) ? .matches : .differs }
        }

        // Titel: mindestens ein markantes Wort (Komponist, Ensemble, Werk).
        let titleTokens = significant(title)
        if !titleTokens.isEmpty { result.title = titleTokens.contains(where: hay.contains) ? .matches : .differs }
        return result
    }

    // MARK: Hilfen

    private static let stopwords: Set<String> = [
        "konzert", "konzerte", "abend", "sinfonie", "symphonie", "nr", "und", "mit", "der", "die", "das", "des", "dem", "den",
        "im", "in", "am", "an", "von", "zum", "zur", "für", "fur", "saal", "halle", "haus", "theater", "kirche", "münchen",
        "munchen", "muenchen", "berlin", "wien", "hamburg", "großer", "grosser", "kleiner", "the", "and", "orchester",
        "chor", "ensemble", "festival", "programm", "musik", "klassik", "philharmonie",
    ]

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .lowercased()
    }

    private static func significant(_ value: String) -> [String] {
        normalize(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopwords.contains($0) && Int($0) == nil }
    }

    private struct FoundDate { let day: Int; let month: Int; let year: Int? }

    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "maer": 3, "mrz": 3, "apr": 4, "mai": 5, "may": 5, "jun": 6, "jul": 7,
        "aug": 8, "sep": 9, "okt": 10, "oct": 10, "nov": 11, "dez": 12, "dec": 12,
    ]

    private static func dates(in text: String) -> [FoundDate] {
        var out: [FoundDate] = []
        let lower = normalize(text)
        // 12.12.2026 · 12.12.26 · 12/12/2026
        for match in lower.matches(of: /\b(\d{1,2})[.\/](\d{1,2})[.\/](\d{2,4})\b/) {
            guard let d = Int(match.1), let m = Int(match.2), var y = Int(match.3), (1...31).contains(d), (1...12).contains(m) else { continue }
            if y < 100 { y += 2000 }
            out.append(FoundDate(day: d, month: m, year: y))
        }
        // 2026-12-12
        for match in lower.matches(of: /\b(20\d{2})-(\d{2})-(\d{2})\b/) {
            guard let y = Int(match.1), let m = Int(match.2), let d = Int(match.3) else { continue }
            out.append(FoundDate(day: d, month: m, year: y))
        }
        // 12. Dezember 2026 · 12 Dec 2026
        for match in lower.matches(of: /\b(\d{1,2})\.?\s+([a-z]{3,9})\.?\s*(20\d{2})?\b/) {
            let name = String(match.2)
            guard let d = Int(match.1), (1...31).contains(d),
                  let m = months.first(where: { name.hasPrefix($0.key) })?.value else { continue }
            out.append(FoundDate(day: d, month: m, year: match.3.flatMap { Int($0) }))
        }
        return out
    }
}
