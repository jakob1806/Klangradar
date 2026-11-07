import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Gestaltung (Nutzerwunsch 24.10.2026): flach, weiß, ein Akzent in
// Klangradar-Blau, klare Typo – keine Verläufe.
private let accent = Color(red: 0.078, green: 0.380, blue: 0.580) // #146194
// 02.11.2026: dynamisch statt fest Schwarz/Weiß – im Dunkelmodus und bei
// getönten Home-Bildschirmen war das Widget sonst ein weißer Block.
private let ink = Color.primary

@main
struct KlangradarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextConcertWidget()
        ConcertLiveActivity()
        if #available(iOS 18.0, *) {
            CoachControl()
            TodayConcertsControl()
        }
    }
}

private func dayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Heute" }
    if calendar.isDateInTomorrow(date) { return "Morgen" }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
}

private func circularLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return clock(date) }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
    return "\(max(days, 1)) T"
}

private func clock(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))) }

// MARK: - Kontrollzentrum & Aktionstaste (iOS 18, 02.11.2026)

@available(iOS 18.0, *)
struct CoachControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "de.klangradar.native.control.coach") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "de.klangradar.native://coach")!)) {
                Label("Klangradar KI", systemImage: "sparkles")
            }
        }
        .displayName("Klangradar KI")
        .description("Öffnet die Klangradar KI für Konzertempfehlungen.")
    }
}

@available(iOS 18.0, *)
struct TodayConcertsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "de.klangradar.native.control.today") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "de.klangradar.native://calendar")!)) {
                Label("Konzerte heute", systemImage: "music.note.list")
            }
        }
        .displayName("Konzerte heute")
        .description("Öffnet den Klangradar-Kalender mit dem heutigen Tag.")
    }
}

// MARK: - Widget "Nächstes Konzert"

struct NextConcertEntry: TimelineEntry {
    let date: Date
    let concerts: [SharedConcert]
}

struct NextConcertProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextConcertEntry {
        NextConcertEntry(date: .now, concerts: [SharedConcert(id: "x", slug: "", title: "Sinfoniekonzert", venue: "Isarphilharmonie", start: .now.addingTimeInterval(86_400))])
    }

    func getSnapshot(in context: Context, completion: @escaping (NextConcertEntry) -> Void) {
        let concerts = SharedConcertStore.load()
        completion(concerts.isEmpty ? placeholder(in: context) : NextConcertEntry(date: .now, concerts: concerts))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextConcertEntry>) -> Void) {
        let concerts = SharedConcertStore.load()
        let next = concerts.first.map { $0.start.addingTimeInterval(3 * 3600) } ?? .now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [NextConcertEntry(date: .now, concerts: concerts)], policy: .after(min(next, .now.addingTimeInterval(3 * 3600)))))
    }
}

struct NextConcertWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextConcert", provider: NextConcertProvider()) { entry in
            NextConcertView(entry: entry).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Nächstes Konzert")
        .description("Deine nächsten gemerkten Konzerte auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextConcertView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextConcertEntry

    var body: some View {
        if let first = entry.concerts.first {
            switch family {
            case .accessoryInline:
                Text("♪ \(dayLabel(first.start)) \(clock(first.start)) · \(first.title)").widgetURL(first.deepLink)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(dayLabel(first.start)) · \(clock(first.start))").font(.caption2.bold())
                    Text(first.title).font(.caption).lineLimit(2)
                }
                .widgetURL(first.deepLink)
            case .accessoryCircular:
                // Countdown in Tagen bzw. Uhrzeit am Konzerttag.
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "music.note").font(.caption2)
                        Text(circularLabel(first.start)).font(.headline.monospacedDigit()).minimumScaleFactor(0.6)
                    }
                }
                .widgetURL(first.deepLink)
            case .systemMedium, .systemLarge:
                VStack(alignment: .leading, spacing: 10) {
                    WidgetHeader(title: "Gemerkt")
                    ForEach(entry.concerts.prefix(family == .systemLarge ? 7 : 3)) { concert in
                        Link(destination: concert.deepLink) { ConcertLine(concert: concert) }
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 3) {
                    WidgetHeader(title: dayLabel(first.start))
                    Spacer(minLength: 0)
                    Text(clock(first.start)).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                    Text(first.title).font(.subheadline.weight(.semibold)).foregroundStyle(ink).lineLimit(2)
                    Text(first.venue).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .widgetURL(first.deepLink)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Gemerkt")
                Spacer(minLength: 0)
                Text("Merke dir Konzerte mit ♡ – sie erscheinen dann hier.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WidgetHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(accent)
        }
    }
}

private struct ConcertLine: View {
    let concert: SharedConcert
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Calendar.current.isDateInToday(concert.start) ? clock(concert.start) : dayLabel(concert.start))
                .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(accent)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(concert.title).font(.subheadline.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
                Text(concert.venue).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Live Activity am Konzerttag

struct ConcertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConcertActivityAttributes.self) { context in
            LockScreenConcertView(attributes: context.attributes, state: context.state)
                // 06.11.2026: dunkel statt Weiß – vorher war weiße Schrift
                // (Dunkelmodus) auf weißem Grund unlesbar.
                .activityBackgroundTint(Color(red: 0.07, green: 0.09, blue: 0.13))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "de.klangradar.native://event/\(context.attributes.slug)"))
        } dynamicIsland: { context in
            let evening = Evening(attributes: context.attributes, state: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(evening.phaseLabel).font(.caption2.weight(.semibold)).foregroundStyle(islandDim)
                        CountdownText(evening: evening, size: 26)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(evening.nextLabel).font(.caption2.weight(.semibold)).foregroundStyle(islandDim)
                        Text(evening.nextClock).font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(context.attributes.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(context.attributes.venue).font(.caption).foregroundStyle(islandDim).lineLimit(1)
                        }
                        StationRow(evening: evening, dim: islandDim, highlight: islandAccent)
                        if let notice = context.state.notice, !notice.isEmpty {
                            Text(notice).font(.caption2.weight(.semibold)).foregroundStyle(islandAccent).lineLimit(1)
                        }
                        if evening.next != nil, !evening.isCancelled {
                            ActivityButton(title: "Ticket zeigen", url: "de.klangradar.native://ticket/\(context.attributes.slug)")
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                PhaseRing(evening: evening).frame(width: 18, height: 18)
            } compactTrailing: {
                CountdownText(evening: evening, size: 15).frame(maxWidth: 58)
            } minimal: {
                PhaseRing(evening: evening).frame(width: 18, height: 18)
            }
            .widgetURL(URL(string: "de.klangradar.native://event/\(context.attributes.slug)"))
        }
    }
}

// MARK: - Konzertabend (06.11.2026)

private let islandDim = Color.white.opacity(0.6)
private let islandAccent = Color(red: 0.45, green: 0.72, blue: 0.95)

/// Stationen des Abends und was gerade dran ist. Reihenfolge: Einlass →
/// Beginn → Pause → 2. Teil → Ende. Die Losgeh-Zeit ist bewusst keine
/// Station mehr (jeder reist anders an).
private struct Evening {
    struct Station: Identifiable {
        let id: String
        let label: String
        let time: Date
        let estimated: Bool
    }

    let attributes: ConcertActivityAttributes
    let state: ConcertActivityAttributes.ContentState
    var now: Date = .now

    /// Beginn, ggf. vom Server geändert.
    var start: Date { state.startAt ?? attributes.start }
    var isCancelled: Bool { state.phase == "cancelled" }

    var stations: [Station] {
        var list: [Station] = []
        if let doors = state.doorsAt { list.append(.init(id: "doors", label: "Einlass", time: doors, estimated: state.doorsEstimated ?? true)) }
        list.append(.init(id: "start", label: "Beginn", time: start, estimated: false))
        if let pause = state.pauseAt { list.append(.init(id: "pause", label: "Pause", time: pause, estimated: true)) }
        if let second = state.pauseEndAt { list.append(.init(id: "second", label: "2. Teil", time: second, estimated: true)) }
        if let end = state.endAt { list.append(.init(id: "end", label: "Ende", time: end, estimated: state.endEstimated ?? true)) }
        return list
    }

    var next: Station? { stations.first { $0.time > now } }
    var previous: Station? { stations.last { $0.time <= now } }

    var phaseLabel: String {
        if isCancelled { return "Abgesagt" }
        guard let next else { return "Konzert vorbei" }
        switch next.id {
        case "doors": return "Einlass in"
        case "start": return previous?.id == "doors" ? "Einlass läuft · Beginn in" : "Beginn in"
        case "pause": return "Pause in ca."
        case "second": return "Pause · noch"
        case "end": return "Ende in ca."
        default: return ""
        }
    }

    var nextLabel: String { next.map { $0.estimated ? "\($0.label) ca." : $0.label } ?? "Ende" }
    var nextClock: String { next.map { clock($0.time) } ?? (state.endAt.map(clock) ?? clock(start)) }

    /// Fortschritt vom letzten bis zum nächsten Schritt.
    var segment: ClosedRange<Date>? {
        guard let next else { return nil }
        let from = previous?.time ?? min(next.time.addingTimeInterval(-3600), now)
        return from < next.time ? from...next.time : nil
    }
}

/// Countdown bis zum nächsten Schritt; ohne nächsten Schritt „Vorbei“.
private struct CountdownText: View {
    let evening: Evening
    let size: CGFloat
    var body: some View {
        if let next = evening.next {
            Text(timerInterval: evening.now...next.time, countsDown: true)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.trailing)
        } else {
            Text("Vorbei").font(.system(size: size, weight: .bold, design: .rounded))
        }
    }
}

/// Ring für kompakte/minimale Dynamic Island: füllt sich bis zum nächsten Schritt.
private struct PhaseRing: View {
    let evening: Evening
    var body: some View {
        if let segment = evening.segment {
            ProgressView(timerInterval: segment, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
                .tint(islandAccent)
        } else {
            Circle().strokeBorder(islandAccent, lineWidth: 2.5)
        }
    }
}

/// Stationen als Zeile: Punkt, Bezeichnung, Uhrzeit; erledigte gedimmt.
private struct StationRow: View {
    let evening: Evening
    let dim: Color
    let highlight: Color
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(evening.stations) { station in
                let done = station.time <= evening.now
                let isNext = station.id == evening.next?.id
                VStack(alignment: .leading, spacing: 2) {
                    Circle().fill(isNext ? highlight : (done ? dim.opacity(0.5) : .white.opacity(0.35)))
                        .frame(width: 6, height: 6)
                    Text(station.label).font(.caption2).foregroundStyle(dim).lineLimit(1)
                    Text((station.estimated ? "~" : "") + clock(station.time))
                        .font(.caption.weight(isNext ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(done ? dim : .white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Sperrbildschirm: Kopf, großer Countdown, Platz, Fortschritt, Stationen.
private struct LockScreenConcertView: View {
    let attributes: ConcertActivityAttributes
    let state: ConcertActivityAttributes.ContentState

    var body: some View {
        let evening = Evening(attributes: attributes, state: state)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(attributes.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                Text(attributes.venue).font(.caption).foregroundStyle(islandDim).lineLimit(1)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(evening.phaseLabel).font(.caption.weight(.semibold)).foregroundStyle(islandDim)
                    CountdownText(evening: evening, size: 34).foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                if let seat = SharedSeatStore.seat(forSlug: attributes.slug) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Dein Platz").font(.caption2).foregroundStyle(islandDim)
                        Text(seat.summary).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                            .multilineTextAlignment(.trailing).lineLimit(2)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(evening.nextLabel).font(.caption2).foregroundStyle(islandDim)
                        Text(evening.nextClock).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                    }
                }
            }
            if let segment = evening.segment {
                ProgressView(timerInterval: segment, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(islandAccent)
            }
            StationRow(evening: evening, dim: islandDim, highlight: islandAccent)
            if let notice = state.notice, !notice.isEmpty {
                Text(notice).font(.caption.weight(.semibold))
                    .foregroundStyle(evening.isCancelled ? Color(red: 1, green: 0.55, blue: 0.5) : islandAccent)
                    .lineLimit(2)
            }
            // Knöpfe (06.11.2026): Ticket mit voller Helligkeit, nach dem
            // Konzert bewerten; beide öffnen die App an der richtigen Stelle.
            HStack(spacing: 8) {
                if evening.next == nil || evening.isCancelled {
                    ActivityButton(title: "Konzert bewerten", url: "de.klangradar.native://event/\(attributes.slug)")
                } else {
                    // 07.11.2026: nur noch ein Knopf, damit es übersichtlich bleibt.
                    ActivityButton(title: "Ticket zeigen", url: "de.klangradar.native://ticket/\(attributes.slug)")
                }
            }
        }
        .padding(14)
    }
}

private struct ActivityButton: View {
    let title: String
    let url: String
    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(.white.opacity(0.14), in: Capsule())
            }
        }
    }
}
