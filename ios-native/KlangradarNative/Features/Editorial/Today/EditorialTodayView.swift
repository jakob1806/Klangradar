import SwiftUI

/// Punkt 17, "Heute"-Modus: nur die HEUTIGEN Veranstaltungen, mit genau den
/// Aktionen, die kurzfristig vor Ort tatsächlich anfallen (ausverkauft,
/// abgesagt, verschoben) — statt durch den vollen Editor mit Programm/
/// Mitwirkenden/Preisen navigieren zu müssen, wenn nur der Status kippt.
struct EditorialTodayView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository

    @State private var events: [EditorialEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var workingEventID: UUID?

    var body: some View {
        ZStack {
            EditorialBackground()
            if isLoading {
                ProgressView("Heutige Veranstaltungen werden geladen …").tint(KlangradarTheme.accent)
            } else if events.isEmpty {
                ContentUnavailableView("Nichts für heute", systemImage: "sun.max", description: Text("Heute sind keine Veranstaltungen angesetzt."))
            } else {
                List {
                    Section {
                        EditorialModeBanner(compact: true)
                    }
                    .listRowBackground(Color.clear)
                    ForEach(events) { event in
                        EditorialTodayRow(
                            event: event,
                            isWorking: workingEventID == event.id,
                            onSetStatus: { status in Task { await apply(status: status, to: event) } },
                            onSetTicketStatus: { ticketStatus in Task { await apply(ticketStatus: ticketStatus, to: event) } }
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Heute")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Änderung nicht gespeichert", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; isLoading = false; return }
        isLoading = events.isEmpty
        defer { isLoading = false }
        do {
            let all = try await repository.events(search: "", token: token)
            let calendar = Calendar.current
            events = all
                .filter { calendar.isDateInToday($0.startDate) }
                .sorted { $0.startDate < $1.startDate }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    /// updateEventDetails() ersetzt immer den vollständigen Feldsatz — daher
    /// erst das aktuelle Detail nachladen und nur das eine geänderte Feld
    /// überschreiben, statt versehentlich Preise/Genres/Beschreibung mit
    /// Leerwerten zu überschreiben.
    @MainActor private func apply(status: String? = nil, ticketStatus: String? = nil, to event: EditorialEvent) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        workingEventID = event.id
        defer { workingEventID = nil }
        do {
            let detail = try await repository.detail(eventID: event.id, token: token)
            let current = detail.event
            try await repository.updateEventDetails(
                event: current,
                descriptionDe: current.descriptionDe ?? "",
                durationMinutes: current.durationMinutes,
                hasIntermission: current.hasIntermission,
                organizerID: current.organizerID,
                genreIDs: current.genreIDs,
                priceMin: current.priceMin,
                priceMax: current.priceMax,
                isFree: current.isFree,
                ticketURL: current.ticketURL ?? "",
                remainingTicketsStatus: ticketStatus ?? current.remainingTicketsStatus ?? "",
                doorsInfo: current.doorsInfo ?? "",
                ageRestriction: current.ageRestriction ?? "",
                discountInfo: current.discountInfo ?? "",
                presaleFeeInfo: current.presaleFeeInfo ?? "",
                status: status ?? current.status,
                actor: actor, token: token
            )
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct EditorialTodayRow: View {
    let event: EditorialEvent
    let isWorking: Bool
    let onSetStatus: (String) -> Void
    let onSetTicketStatus: (String) -> Void

    var body: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text(KlangradarDateTime.string(event.startDate, format: "HH:mm"))
                    .font(.headline).foregroundStyle(KlangradarTheme.accent)
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(event.venueName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if event.status != "scheduled" { statusBadge(label(forStatus: event.status), color: .red) }
                    if let ticketStatus = event.remainingTicketsStatus, !ticketStatus.isEmpty {
                        statusBadge(label(forTicketStatus: ticketStatus), color: .orange)
                    }
                }
            }
            Spacer()
            if isWorking {
                ProgressView()
            } else {
                Menu {
                    Button("Als ausverkauft markieren", systemImage: "flame") { onSetTicketStatus("sold_out") }
                    Button("Nur noch wenige Tickets", systemImage: "exclamationmark.triangle") { onSetTicketStatus("few_left") }
                    Divider()
                    Button("Absagen", systemImage: "xmark.octagon", role: .destructive) { onSetStatus("cancelled") }
                    Button("Verschieben", systemImage: "calendar.badge.exclamationmark") { onSetStatus("postponed") }
                    if event.status != "scheduled" {
                        Button("Status zurücksetzen", systemImage: "arrow.uturn.backward") { onSetStatus("scheduled") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(KlangradarTheme.accent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func label(forStatus status: String) -> String {
        switch status {
        case "cancelled": "Abgesagt"
        case "postponed": "Verschoben"
        case "draft": "Entwurf"
        case "sold_out": "Ausverkauft"
        default: status
        }
    }

    private func label(forTicketStatus status: String) -> String {
        switch status {
        case "sold_out": "Ausverkauft"
        case "few_left": "Fast ausverkauft"
        case "box_office_only": "Nur Abendkasse"
        default: status
        }
    }
}
