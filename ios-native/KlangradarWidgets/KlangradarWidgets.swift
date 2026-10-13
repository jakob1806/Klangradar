import ActivityKit
import SwiftUI
import WidgetKit

@main
struct KlangradarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextConcertWidget()
        ConcertLiveActivity()
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
        // Neu berechnen, sobald das nächste Konzert vorbei ist, spätestens in 6 h.
        let next = concerts.first.map { $0.start.addingTimeInterval(3 * 3600) } ?? .now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [NextConcertEntry(date: .now, concerts: concerts)], policy: .after(min(next, .now.addingTimeInterval(6 * 3600)))))
    }
}

struct NextConcertWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextConcert", provider: NextConcertProvider()) { entry in
            NextConcertView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.11, green: 0.10, blue: 0.29), Color(red: 0.18, green: 0.16, blue: 0.43)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Nächstes Konzert")
        .description("Deine nächsten gemerkten Konzerte auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private func dayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Heute" }
    if calendar.isDateInTomorrow(date) { return "Morgen" }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
}

struct NextConcertView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextConcertEntry

    var body: some View {
        if let first = entry.concerts.first {
            switch family {
            case .accessoryInline:
                Text("♪ \(dayLabel(first.start)) \(first.start.formatted(date: .omitted, time: .shortened)) · \(first.title)")
                    .widgetURL(first.deepLink)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(dayLabel(first.start)) · \(first.start.formatted(date: .omitted, time: .shortened))").font(.caption2.bold())
                    Text(first.title).font(.caption).lineLimit(2)
                }
                .widgetURL(first.deepLink)
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    header
                    ForEach(entry.concerts.prefix(3)) { concert in
                        Link(destination: concert.deepLink) { row(concert) }
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    header
                    Spacer(minLength: 0)
                    Text("\(dayLabel(first.start)) · \(first.start.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
                    Text(first.title).font(.headline).foregroundStyle(.white).lineLimit(3)
                    Text(first.venue).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                .widgetURL(first.deepLink)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                Text("Merke dir Konzerte mit ♡ – sie erscheinen dann hier.")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var header: some View {
        Label("Klangradar", systemImage: "music.note")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
    }

    private func row(_ concert: SharedConcert) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayLabel(concert.start)).font(.caption.bold()).foregroundStyle(.white.opacity(0.8)).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(concert.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(concert.start.formatted(date: .omitted, time: .shortened)) · \(concert.venue)").font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        }
    }
}

// MARK: - Live Activity am Konzerttag

struct ConcertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConcertActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "music.note").font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(red: 0.18, green: 0.16, blue: 0.43), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Text(context.attributes.venue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.attributes.start, style: .time).font(.headline.monospacedDigit())
                    if context.attributes.start > .now {
                        Text(timerInterval: Date.now...context.attributes.start, countsDown: true).font(.caption.monospacedDigit()).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    } else {
                        Text("läuft").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .widgetURL(URL(string: "de.klangradar.native://event/\(context.attributes.slug)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note").font(.title3)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.start, style: .time).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        Text(context.attributes.venue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Text(context.attributes.start, style: .time).monospacedDigit()
            } minimal: {
                Image(systemName: "music.note")
            }
            .widgetURL(URL(string: "de.klangradar.native://event/\(context.attributes.slug)"))
        }
    }
}
