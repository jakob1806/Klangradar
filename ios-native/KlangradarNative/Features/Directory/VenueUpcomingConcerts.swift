// Erstellt von Claude Code (Nutzerwunsch 01.11.2026): "Kommende Konzerte"
// auf der Seite einer Spielstätte neu – vorher eine lange, monatsweise
// aufklappbare Liste, in der man nichts schnell fand. Jetzt: Zeitraum-Chips
// (Diese Woche, Wochenende, Monate), Suche ab vielen Terminen und kompakte
// Zeilen mit Bild, Wochentag und Komponist:innen.
import SwiftUI

struct VenueUpcomingConcerts: View {
    let events: [LinkedEvent]
    var exportURL: URL? = nil

    private enum Range: Hashable {
        case all, thisWeek, weekend
        case month(Date)
    }

    @State private var range: Range = .all
    @State private var query = ""
    @State private var visibleLimit = 8

    private let calendar = KlangradarDateTime.calendar

    private var upcoming: [LinkedEvent] {
        events
            .filter { ($0.startDate ?? .distantPast) >= calendar.startOfDay(for: .now) }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var months: [(month: Date, count: Int)] {
        let grouped = Dictionary(grouping: upcoming) { event in
            event.startDate.flatMap { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) } ?? .distantFuture
        }
        return grouped.keys.filter { $0 != .distantFuture }.sorted().prefix(8).map { ($0, grouped[$0]?.count ?? 0) }
    }

    private var filtered: [LinkedEvent] {
        let now = Date.now
        let byRange = upcoming.filter { event in
            guard let date = event.startDate else { return range == .all }
            switch range {
            case .all:
                return true
            case .thisWeek:
                return date < calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))!
            case .weekend:
                let weekday = calendar.component(.weekday, from: date) // 1 = So, 6 = Fr, 7 = Sa
                let inNextWeek = date < calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now))!
                return inNextWeek && (weekday == 1 || weekday == 7 || (weekday == 6 && calendar.component(.hour, from: date) >= 17))
            case .month(let month):
                return calendar.isDate(date, equalTo: month, toGranularity: .month)
            }
        }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return byRange }
        return byRange.filter { event in
            event.title.localizedStandardContains(needle)
                || event.programWorks.contains { ($0.composerName ?? "").localizedStandardContains(needle) || $0.title.localizedStandardContains(needle) }
        }
    }

    var body: some View {
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Kommende Konzerte").font(.title2.bold())
                    Text("\(upcoming.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(KlangradarTheme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
                    Spacer()
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Image(systemName: "calendar.badge.plus").font(.title3)
                        }
                        .tint(KlangradarTheme.accent)
                        .accessibilityLabel("Alle Konzerte in den Kalender exportieren")
                    }
                }

                if upcoming.count > 12 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Werk, Komponist:in oder Titel", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .accessibilityLabel("Suche leeren")
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        chip("Alle", count: upcoming.count, value: .all)
                        chip("Diese Woche", count: nil, value: .thisWeek)
                        chip("Wochenende", count: nil, value: .weekend)
                        ForEach(months, id: \.month) { item in
                            chip(KlangradarDateTime.string(item.month, format: "MMM yy"), count: item.count, value: .month(item.month))
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if filtered.isEmpty {
                    Text(query.isEmpty ? "In diesem Zeitraum keine Konzerte." : "Keine Treffer für „\(query)“.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    LiquidGlassSurface(cornerRadius: 22) {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.prefix(visibleLimit).enumerated()), id: \.element.id) { index, event in
                                row(event)
                                if index < min(filtered.count, visibleLimit) - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                    }
                    if filtered.count > visibleLimit {
                        Button {
                            withAnimation { visibleLimit += 12 }
                        } label: {
                            Text("Weitere \(min(12, filtered.count - visibleLimit)) von \(filtered.count - visibleLimit) anzeigen")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(KlangradarTheme.accent.opacity(0.1), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(KlangradarTheme.accent)
                    }
                }
            }
            .onChange(of: range) { _, _ in visibleLimit = 8 }
            .onChange(of: query) { _, _ in visibleLimit = 8 }
        }
    }

    private func chip(_ title: String, count: Int?, value: Range) -> some View {
        let isSelected = range == value
        return Button {
            Haptics.light()
            withAnimation(.snappy(duration: 0.2)) { range = value }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                if let count {
                    Text("\(count)").monospacedDigit().opacity(0.7)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func row(_ event: LinkedEvent) -> some View {
        if let concert = event.concertEvent {
            // Einheitliche Konzertzeile (02.11.2026), sobald das Konzert geladen ist.
            NavigationLink(value: concert) { ConcertRow(event: concert) }
                .buttonStyle(.plain)
        } else {
            rowLabel(event, concert: nil)
        }
    }

    private func rowLabel(_ event: LinkedEvent, concert: ConcertEvent?) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(event.startDate.map { KlangradarDateTime.string($0, format: "EEE") } ?? "")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(KlangradarTheme.accent)
                Text(event.startDate.map { KlangradarDateTime.string($0, format: "d") } ?? "–")
                    .font(.title3.bold().monospacedDigit())
                Text(event.startDate.map { KlangradarDateTime.string($0, format: "MMM") } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40)

            Group {
                if let concert {
                    EventArtwork(event: concert)
                } else {
                    Color.secondary.opacity(0.12)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle(event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    /// "20:00 · Beethoven, Brahms" – Uhrzeit und bis zu drei Komponist:innen.
    private func subtitle(_ event: LinkedEvent) -> String {
        var parts: [String] = []
        if let date = event.startDate { parts.append(KlangradarDateTime.string(date, format: "HH:mm")) }
        var seen = Set<String>()
        let composers = event.programWorks.compactMap { $0.composerName?.split(separator: " ").last.map(String.init) }
            .filter { seen.insert($0).inserted }
        if !composers.isEmpty { parts.append(composers.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
