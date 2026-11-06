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

/// Konzertabend-Cockpit (06.11.2026): alles Zeitliche auf einen Blick –
/// großer Countdown zum nächsten Schritt, Fortschritt bis zum Beginn,
/// Fahrzeit, Platz und die Stationen des Abends. Kein Bild.
private struct LockScreenConcertView: View {
    let attributes: ConcertActivityAttributes
    let state: ConcertActivityAttributes.ContentState

    private let dim = Color.white.opacity(0.65)

    var body: some View {
        let now = Date.now
        let leave = state.leaveAt.flatMap { $0 > now ? $0 : nil }
        VStack(alignment: .leading, spacing: 10) {
            // Kopf: Titel · Ort
            HStack(spacing: 6) {
                Image(systemName: "music.note").font(.caption.weight(.bold)).foregroundStyle(accentLight)
                Text(attributes.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                Text(attributes.venue).font(.caption).foregroundStyle(dim).lineLimit(1)
            }

            // Mitte: Countdown links, Fakten rechts
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(phaseLabel(now: now, leave: leave)).font(.caption.weight(.semibold)).foregroundStyle(dim)
                    if let target = countdownTarget(now: now, leave: leave) {
                        Text(timerInterval: now...target, countsDown: true)
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    } else {
                        Text(attributes.start > now ? clock(attributes.start) : "Läuft")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    fact("clock", "Beginn \(clock(attributes.start))")
                    if let travel = state.travel, leave != nil { fact("tram.fill", travel) }
                    if let seat = SharedSeatStore.seat(forSlug: attributes.slug) { fact("chair.fill", seat.summary) }
                }
            }

            // Fortschritt: Losgehen → Beginn (bzw. Beginn → Pause)
            if let range = progressRange(now: now) {
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(accentLight)
            }

            // Stationen des Abends
            HStack(spacing: 0) {
                if let planned = state.leaveAt { station("Losgehen", planned, done: planned <= now) }
                station("Beginn", attributes.start, done: attributes.start <= now)
                if let pause = state.pauseAt { station("Pause ca.", pause, done: pause <= now) }
            }
        }
        .padding(14)
    }

    private var accentLight: Color { Color(red: 0.45, green: 0.72, blue: 0.95) }

    private func phaseLabel(now: Date, leave: Date?) -> String {
        if leave != nil { return "Losgehen in" }
        if attributes.start > now { return "Beginn in" }
        if let pause = state.pauseAt, pause > now { return "Pause in ca." }
        return "Konzert"
    }

    private func countdownTarget(now: Date, leave: Date?) -> Date? {
        if let leave { return leave }
        if attributes.start > now { return attributes.start }
        if let pause = state.pauseAt, pause > now { return pause }
        return nil
    }

    private func progressRange(now: Date) -> ClosedRange<Date>? {
        if attributes.start > now {
            let from = min(state.leaveAt ?? attributes.start.addingTimeInterval(-3600), now)
            return from...attributes.start
        }
        if let pause = state.pauseAt, pause > now { return attributes.start...pause }
        return nil
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            .lineLimit(1).labelStyle(TrailingIconLabel())
    }

    private func station(_ label: String, _ time: Date, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(dim)
            HStack(spacing: 3) {
                if done { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(accentLight) }
                Text(clock(time)).font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(done ? dim : .white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.font(.caption2) }
    }
}
