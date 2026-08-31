import Foundation

/// Baut .ics-Dateien für den Kalender-Export (Nutzerwunsch: Export für ein
/// einzelnes Konzert sowie gesammelt für alle Konzerte einer gefolgten
/// Person/eines Ensembles/eines Orts). Portiert das Format 1:1 aus
/// app/lib/core/calendar/ics_export.dart, damit iOS und Flutter identische
/// .ics-Dateien erzeugen.
struct IcsEventInput {
    let uid: String
    let title: String
    let start: Date
    var end: Date? = nil
    var durationMinutes: Int = 120
    var description: String? = nil
    var location: String? = nil
    var url: String? = nil

    var effectiveEnd: Date { end ?? start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

enum IcsExport {
    /// Schreibt die .ics-Datei in ein temporäres Verzeichnis und liefert die
    /// Datei-URL zurück, die z.B. per `ShareLink(item:)` geteilt werden kann.
    static func write(_ events: [IcsEventInput], fileName: String) throws -> URL {
        let ics = build(events)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try ics.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func build(_ events: [IcsEventInput]) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Klangradar//DE"]
        let stamp = formatUTC(Date())
        for event in events {
            lines.append(contentsOf: [
                "BEGIN:VEVENT",
                "UID:\(event.uid)@klassikmuenchen.de",
                "DTSTAMP:\(stamp)",
                "DTSTART:\(formatUTC(event.start))",
                "DTEND:\(formatUTC(event.effectiveEnd))",
                "SUMMARY:\(escape(event.title))"
            ])
            if let description = event.description, !description.isEmpty {
                lines.append("DESCRIPTION:\(escape(description))")
            }
            if let location = event.location, !location.isEmpty {
                lines.append("LOCATION:\(escape(location))")
            }
            if let url = event.url, !url.isEmpty {
                lines.append("URL:\(url)")
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private static func formatUTC(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return "\(components.year ?? 0)\(pad(components.month))\(pad(components.day))T\(pad(components.hour))\(pad(components.minute))\(pad(components.second))Z"
    }

    /// RFC 5545 §3.3.11 — Reihenfolge wichtig, Backslash zuerst escapen.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
