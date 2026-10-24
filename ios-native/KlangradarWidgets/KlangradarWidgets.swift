import ActivityKit
import SwiftUI
import WidgetKit

// Gestaltung (Nutzerwunsch 24.10.2026): flach, weiß, ein Akzent in
// Klangradar-Blau, klare Typo – keine Verläufe.
private let accent = Color(red: 0.078, green: 0.380, blue: 0.580) // #146194
private let ink = Color(red: 0.07, green: 0.08, blue: 0.10)

@main
struct KlangradarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextConcertWidget()
        TonightWidget()
        ConcertLiveActivity()
    }
}

private func dayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Heute" }
    if calendar.isDateInTomorrow(date) { return "Morgen" }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
}

private func clock(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))) }

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
            NextConcertView(entry: entry).containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Nächstes Konzert")
        .description("Deine nächsten gemerkten Konzerte auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
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
            case .systemMedium:
                VStack(alignment: .leading, spacing: 10) {
                    WidgetHeader(title: "Gemerkt")
                    ForEach(entry.concerts.prefix(3)) { concert in
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

// MARK: - Widget "Heute Abend"

struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextConcertEntry {
        NextConcertEntry(date: .now, concerts: [SharedConcert(id: "x", slug: "", title: "Kammerkonzert", venue: "Herkulessaal", start: .now.addingTimeInterval(7200))])
    }
    func getSnapshot(in context: Context, completion: @escaping (NextConcertEntry) -> Void) {
        let concerts = SharedTonightStore.load()
        completion(concerts.isEmpty ? placeholder(in: context) : NextConcertEntry(date: .now, concerts: concerts))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextConcertEntry>) -> Void) {
        let concerts = SharedTonightStore.load()
        let next = concerts.first?.start ?? .now.addingTimeInterval(3 * 3600)
        completion(Timeline(entries: [NextConcertEntry(date: .now, concerts: concerts)], policy: .after(min(next, .now.addingTimeInterval(2 * 3600)))))
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Tonight", provider: TonightProvider()) { entry in
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Heute Abend")
                if entry.concerts.isEmpty {
                    Spacer(minLength: 0)
                    Text("Öffne „Heute Abend“ in Klangradar, um zu sehen, was noch geht.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entry.concerts.prefix(3)) { concert in
                        Link(destination: concert.deepLink) { ConcertLine(concert: concert) }
                    }
                }
                Spacer(minLength: 0)
            }
            .containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Heute Abend")
        .description("Konzerte, die heute noch stattfinden.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Live Activity am Konzerttag

struct ConcertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConcertActivityAttributes.self) { context in
            LockScreenConcertView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(accent)
                .widgetURL(URL(string: "de.klangradar.native://event/\(context.attributes.slug)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(primaryLabel(context.state, start: context.attributes.start)).font(.caption2).foregroundStyle(.secondary)
                        Text(clock(primaryTime(context.state, start: context.attributes.start))).font(.title2.weight(.semibold).monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Beginn").font(.caption2).foregroundStyle(.secondary)
                        Text(clock(context.attributes.start)).font(.title2.weight(.semibold).monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        Text([context.state.travel, context.attributes.venue].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.leaveAt.map { $0 > .now } == true ? "figure.walk" : "music.note").foregroundStyle(accent)
            } compactTrailing: {
                Text(clock(primaryTime(context.state, start: context.attributes.start))).monospacedDigit()
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(accent)
            }
            .widgetURL(URL(string: "de.klangradar.native://event/\(context.attributes.slug)"))
        }
    }
}

/// Was gerade zählt: vor der Losgeh-Zeit "Losgehen", danach "Beginn",
/// während des Konzerts die Pause.
private func primaryTime(_ state: ConcertActivityAttributes.ContentState, start: Date) -> Date {
    if let leave = state.leaveAt, leave > .now { return leave }
    if start > .now { return start }
    if let pause = state.pauseAt, pause > .now { return pause }
    return start
}

private func primaryLabel(_ state: ConcertActivityAttributes.ContentState, start: Date) -> String {
    if let leave = state.leaveAt, leave > .now { return "Losgehen" }
    if start > .now { return "Beginn" }
    if let pause = state.pauseAt, pause > .now { return "Pause ca." }
    return "Läuft"
}

private struct LockScreenConcertView: View {
    let attributes: ConcertActivityAttributes
    let state: ConcertActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(attributes.title).font(.headline).foregroundStyle(ink).lineLimit(1)
                Spacer()
                Text(attributes.venue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 0) {
                step("Losgehen", state.leaveAt, active: (state.leaveAt ?? .distantPast) > .now)
                line
                step("Beginn", attributes.start, active: (state.leaveAt ?? .distantPast) <= .now && attributes.start > .now)
                if state.pauseAt != nil {
                    line
                    step("Pause", state.pauseAt, active: attributes.start <= .now)
                }
            }
            if let travel = state.travel, (state.leaveAt ?? .distantPast) > .now {
                Text(travel).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var line: some View {
        Rectangle().fill(accent.opacity(0.25)).frame(height: 2).frame(maxWidth: .infinity).padding(.horizontal, 6).padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private func step(_ label: String, _ time: Date?, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Circle().fill(active ? accent : accent.opacity(0.25)).frame(width: 10, height: 10).padding(.bottom, 4)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(time.map(clock) ?? "–").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(active ? accent : ink)
        }
        .fixedSize()
    }
}
