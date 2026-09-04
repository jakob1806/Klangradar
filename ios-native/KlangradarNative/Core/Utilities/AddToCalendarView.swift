import EventKit
import EventKitUI
import SwiftUI

/// Nutzerfeedback: "nicht nur ein Popup mit der Downloadmöglichkeit der
/// .ics-Datei" — für ein einzelnes Konzert öffnet sich jetzt Apples eigener
/// Kalender-Editor (EKEventEditViewController, derselbe, den z.B. Mail für
/// erkannte Termine zeigt) direkt in der App, mit "Hinzufügen" oben rechts.
/// IcsExport/.ics-Dateien bleiben für den SAMMEL-Export mehrerer Termine
/// (gefolgte Person/Ensemble/Ort) bestehen — dafür gibt es in EventKit kein
/// entsprechendes Mehrfach-Editor-UI.
private struct AddToCalendarSheet: UIViewControllerRepresentable {
    let event: EKEvent
    let eventStore: EKEventStore
    let onFinish: @MainActor @Sendable () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.event = event
        controller.eventStore = eventStore
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    // NICHT @MainActor: EKEventEditViewDelegate selbst ist nicht isoliert,
    // eine als @MainActor markierte Konformität dazu verletzt unter Swift 6
    // strict concurrency die Protokoll-Isolation. UIKit ruft Delegate-
    // Methoden ohnehin immer auf dem Main Thread auf — Task { @MainActor in }
    // macht das für den Compiler explizit, statt es zu erzwingen.
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: @MainActor @Sendable () -> Void
        init(onFinish: @escaping @MainActor @Sendable () -> Void) { self.onFinish = onFinish }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            // Explizit lokal binden statt onFinish() im Task-Closure über
            // self.onFinish aufzurufen — sonst müsste self (NSObject, nicht
            // Sendable) mit in den Task gesendet werden. @MainActor @Sendable
            // auf dem Closure-Typ selbst macht das Senden über die
            // Task-Grenze zulässig, ohne self zu berühren.
            let finish = onFinish
            Task { @MainActor in
                controller.dismiss(animated: true)
                finish()
            }
        }
    }
}

/// Dieselben Felder wie IcsEventInput (siehe IcsExport.swift), damit beide
/// Wege (Einzeltermin nativ, Sammelexport als .ics) aus denselben Daten
/// gespeist werden können.
struct CalendarEventInput {
    let title: String
    let start: Date
    var end: Date? = nil
    var durationMinutes: Int = 120
    var notes: String? = nil
    var location: String? = nil
    var url: URL? = nil

    var effectiveEnd: Date { end ?? start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

/// Button, der beim Antippen (nach Kalender-Berechtigung) direkt Apples
/// natives "Termin hinzufügen"-Sheet für EIN Konzert öffnet.
struct AddToCalendarButton<Label: View>: View {
    private let input: CalendarEventInput
    private let onHapticTap: () -> Void
    private let label: () -> Label

    @State private var eventStore = EKEventStore()
    @State private var pendingEvent: EKEvent?
    @State private var errorMessage: String?

    init(
        _ input: CalendarEventInput,
        onHapticTap: @escaping () -> Void = { Haptics.light() },
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.input = input
        self.onHapticTap = onHapticTap
        self.label = label
    }

    var body: some View {
        Button {
            onHapticTap()
            Task { await requestAccessAndPresent() }
        } label: { label() }
            .sheet(item: $pendingEvent) { event in
                AddToCalendarSheet(event: event, eventStore: eventStore) { pendingEvent = nil }
            }
            .alert("Kalenderzugriff", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @MainActor
    private func requestAccessAndPresent() async {
        do {
            // writeOnly reicht zum Anlegen eines Termins und braucht keine
            // Leseberechtigung für den restehenden Kalender des Nutzers
            // (schmalere, für diesen Zweck passendere Berechtigung als
            // requestFullAccessToEvents).
            let granted = try await eventStore.requestWriteOnlyAccessToEvents()
            guard granted else {
                errorMessage = "Bitte erlaube Klangradar in den iPhone-Einstellungen den Kalenderzugriff, um Konzerte hinzuzufügen."
                return
            }
        } catch {
            errorMessage = "Der Kalenderzugriff konnte nicht angefragt werden."
            return
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = input.title
        event.startDate = input.start
        event.endDate = input.effectiveEnd
        event.notes = input.notes
        event.location = input.location
        event.url = input.url
        event.calendar = eventStore.defaultCalendarForNewEvents
        pendingEvent = event
    }
}

extension EKEvent: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
