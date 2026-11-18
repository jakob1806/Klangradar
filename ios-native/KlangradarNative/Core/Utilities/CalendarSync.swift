// Erstellt von Claude Code (18.11.2026): Kalender-Abgleich – Überschneidungen
// mit eigenen Terminen erkennen und Konzerte mit Ticket automatisch eintragen.
// Beides nur nach Einschalten in Profil → Einstellungen → Kalender.
import EventKit
import SwiftUI

@MainActor
enum CalendarSync {
    static let conflictKey = "calendarConflictCheck"
    static let autoAddKey = "calendarAutoAddTickets"
    private static let store = EKEventStore()

    static var hasFullAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        if hasFullAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Eigene Termine, die sich mit dem Konzert überschneiden (ohne den
    /// Klangradar-Eintrag desselben Konzerts).
    static func conflicts(start: Date, end: Date, slug: String) -> [EKEvent] {
        guard hasFullAccess, UserDefaults.standard.bool(forKey: conflictKey) else { return [] }
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-30 * 60), end: end, calendars: nil)
        return store.events(matching: predicate).filter { event in
            !event.isAllDay && !(event.url?.absoluteString.contains("/e/\(slug)") ?? false) && event.availability != .free
        }
    }

    /// Konzert mit Ticket eintragen, falls noch nicht vorhanden.
    static func addIfNeeded(title: String, start: Date, end: Date, location: String?, slug: String) {
        guard hasFullAccess, UserDefaults.standard.bool(forKey: autoAddKey) else { return }
        let marker = URL(string: "https://klangradar.com/e/\(slug)")
        let existing = store.events(matching: store.predicateForEvents(withStart: start.addingTimeInterval(-3600), end: end.addingTimeInterval(3600), calendars: nil))
        guard !existing.contains(where: { $0.url == marker }) else { return }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = location
        event.url = marker
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -2 * 3600))
        try? store.save(event, span: .thisEvent)
    }
}

/// Hinweis auf der Konzertseite bei Überschneidung mit eigenen Terminen.
struct CalendarConflictNote: View {
    let event: ConcertEvent
    @State private var titles: [String] = []

    var body: some View {
        Group {
            if !titles.isEmpty {
                Label {
                    Text("Überschneidung mit deinem Termin „\(titles.prefix(2).joined(separator: "“, „"))“")
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.orange)
                }
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
        .task(id: event.id) {
            guard let start = event.startDate, start > .now else { return }
            let end = start.addingTimeInterval(2.5 * 3600)
            titles = CalendarSync.conflicts(start: start, end: end, slug: event.slug).compactMap(\.title)
        }
    }
}

/// Einstellungen: Profil → Einstellungen → Kalender.
struct CalendarSettingsView: View {
    @AppStorage(CalendarSync.conflictKey) private var conflictCheck = false
    @AppStorage(CalendarSync.autoAddKey) private var autoAdd = false
    @State private var denied = false

    var body: some View {
        Form {
            Section {
                Toggle("Überschneidungen anzeigen", isOn: binding($conflictCheck))
                Toggle("Konzerte mit Ticket eintragen", isOn: binding($autoAdd))
            } footer: {
                Text("Klangradar liest deine Termine nur auf dem iPhone, um Überschneidungen zu zeigen. Konzerte, für die du ein Ticket hinterlegst, landen mit Erinnerung zwei Stunden vorher in deinem Standardkalender.")
            }
            if denied {
                Section {
                    Button("Zugriff in den Einstellungen erlauben") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } footer: {
                    Text("Der Kalenderzugriff wurde abgelehnt.")
                }
            }
        }
        .navigationTitle("Kalender")
    }

    private func binding(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { newValue in
            guard newValue else { value.wrappedValue = false; return }
            Task {
                let granted = await CalendarSync.requestAccess()
                value.wrappedValue = granted
                denied = !granted
            }
        })
    }
}
