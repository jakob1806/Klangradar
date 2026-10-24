// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkt 8).
import CoreLocation
import SwiftUI
import WidgetKit

/// "Heute Abend noch was frei?": Konzerte der nächsten Stunden, sortiert
/// danach, ob man sie vom aktuellen Standort aus noch rechtzeitig erreicht.
/// Fahrzeit hier bewusst als schnelle Schätzung aus der Luftlinie (viele
/// Ziele auf einmal; die genaue Route zeigt der Abendfahrplan im Konzert).
struct TonightView: View {
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    let regionID: UUID?

    @State private var rows: [TonightRow] = []
    @State private var isLoading = true
    @State private var hasLocation = false
    @State private var showsTomorrow = false

    struct TonightRow: Identifiable {
        var id: UUID { event.id }
        let event: ConcertEvent
        let start: Date
        let travelMinutes: Int?
        let travelLabel: String?
        var leaveAt: Date? { travelMinutes.map { start.addingTimeInterval(TimeInterval(-($0 + 15) * 60)) } }
        var reachable: Bool { (leaveAt ?? start.addingTimeInterval(-15 * 60)) > Date() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(KlangradarDateTime.string(showsTomorrow ? Date().addingTimeInterval(86_400) : Date(), format: "EEEE, d. MMMM"))
                        .font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(1.2)
                        .foregroundStyle(KlangradarTheme.accent)
                    Text(showsTomorrow ? "Morgen" : "Heute Abend").font(.system(size: 38, weight: .bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if rows.isEmpty {
                    Text("Für heute ist nichts mehr zu erreichen. Morgen gibt es neue Abende.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.top, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            NavigationLink(value: row.event) { TonightRowView(row: row) }
                                .buttonStyle(.plain)
                            if row.id != rows.last?.id { Divider().padding(.leading, 76) }
                        }
                    }
                }
                if !hasLocation && !isLoading {
                    Label("Mit Standortfreigabe siehst du, was du noch rechtzeitig erreichst.", systemImage: "location")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var subtitle: String {
        let reachable = rows.filter(\.reachable).count
        if isLoading { return "Wir schauen, was noch geht …" }
        if showsTomorrow { return "Heute ist nichts mehr erreichbar – das gibt es morgen" }
        return reachable == 1 ? "1 Konzert, das du noch erreichst" : "\(reachable) Konzerte, die du noch erreichst"
    }

    private func load() async {
        defer { isLoading = false }
        await load(day: Date())
        if rows.isEmpty {
            showsTomorrow = true
            await load(day: Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 6 * 3600))
        } else {
            showsTomorrow = false
        }
    }

    private func load(day: Date) async {
        let now = day
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(26 * 3600)
        async let eventsResult = try? repository.events(from: now.addingTimeInterval(-10 * 60), to: end, regionID: regionID)
        async let venuesResult = try? contentRepository.venueLocations(cityID: regionID)
        let events = await eventsResult ?? []
        let venues = Dictionary(((await venuesResult) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let status = CLLocationManager().authorizationStatus
        let here = (status == .authorizedWhenInUse || status == .authorizedAlways) ? CLLocationManager().location : nil
        hasLocation = here != nil

        rows = events.compactMap { event -> TonightRow? in
            guard let start = event.startDate, start > now, Calendar.current.isDate(start, inSameDayAs: now) || start < end else { return nil }
            var minutes: Int?
            var label: String?
            if let here, let venueID = event.venues?.id, let venue = venues[venueID] {
                let meters = here.distance(from: CLLocation(latitude: venue.latitude, longitude: venue.longitude))
                if meters < 1600 {
                    minutes = max(2, Int((meters * 1.25 / 80).rounded())); label = "zu Fuß"
                } else {
                    minutes = Int((meters * 1.3 / 1000 / 18 * 60).rounded()) + 8; label = "mit ÖPNV"
                }
            }
            return TonightRow(event: event, start: start, travelMinutes: minutes, travelLabel: label)
        }
        .filter(\.reachable)
        .sorted { ($0.leaveAt ?? $0.start) < ($1.leaveAt ?? $1.start) }

        guard Calendar.current.isDateInToday(day) else { return }
        SharedTonightStore.save(rows.prefix(6).map {
            SharedConcert(id: $0.event.id.uuidString.lowercased(), slug: $0.event.slug, title: $0.event.title, venue: $0.event.venueName, start: $0.start)
        })
        WidgetCenter.shared.reloadTimelines(ofKind: "Tonight")
    }
}

private struct TonightRowView: View {
    let row: TonightView.TonightRow

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.start, format: .dateTime.hour().minute())
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                if let price = row.event.priceLabel {
                    Text(price).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.event.title).font(.headline).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                Text(row.event.venueName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let leave = row.leaveAt, let minutes = row.travelMinutes, let label = row.travelLabel {
                    let soon = leave.timeIntervalSinceNow < 20 * 60
                    Text(soon ? "Jetzt los · ca. \(minutes) Min. \(label)" : "Los bis \(leave.formatted(date: .omitted, time: .shortened)) · ca. \(minutes) Min. \(label)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(soon ? Color.orange : KlangradarTheme.accent)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

/// Einstieg auf Home: schlichte, flache Kachel statt Banner.
struct TonightEntryCard: View {
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.stars")
                .font(.title3.weight(.semibold))
                .foregroundStyle(KlangradarTheme.accent)
                .frame(width: 44, height: 44)
                .background(KlangradarTheme.accent.opacity(0.1), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Heute Abend noch was frei?").font(.headline).foregroundStyle(.primary)
                Text(count > 0 ? "\(count) Konzerte heute – was du noch erreichst" : "Was du von hier noch erreichst")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
    }
}
