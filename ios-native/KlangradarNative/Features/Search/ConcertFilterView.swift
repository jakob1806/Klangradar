import SwiftUI

/// Konzerte filtern (02.11.2026): Zeitraum, Preis, Genre, Spielstätte.
/// Arbeitet auf der bereits geladenen Liste aller kommenden Konzerte der
/// Suche – kein zusätzlicher Serverabruf, Ergebnis sofort.
struct ConcertFilterView: View {
    let events: [ConcertEvent]

    enum Period: String, CaseIterable, Identifiable {
        case all = "Alle", today = "Heute", tomorrow = "Morgen", weekend = "Wochenende", week = "7 Tage", month = "30 Tage"
        var id: String { rawValue }
    }

    enum Price: String, CaseIterable, Identifiable {
        case all = "Alle Preise", free = "Kostenlos", upTo20 = "bis 20 €", upTo50 = "bis 50 €"
        var id: String { rawValue }
    }

    @State private var period: Period = .all
    @State private var price: Price = .all
    @State private var genre: String?
    @State private var venue: String?
    @State private var text = ""

    private var genres: [String] {
        Array(Set(events.flatMap(\.genreLabels))).sorted()
    }

    private var venues: [String] {
        let counts = Dictionary(grouping: events.map(\.venueName).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(40).map(\.key).sorted()
    }

    private var results: [ConcertEvent] {
        let calendar = KlangradarDateTime.calendar
        let now = Date()
        return events.filter { event in
            guard let start = event.startDate, start >= now.addingTimeInterval(-3600) else { return false }
            switch period {
            case .all: break
            case .today: guard calendar.isDateInToday(start) else { return false }
            case .tomorrow: guard calendar.isDateInTomorrow(start) else { return false }
            case .weekend: guard calendar.isDateInWeekend(start), start < now.addingTimeInterval(7 * 86_400) else { return false }
            case .week: guard start < now.addingTimeInterval(7 * 86_400) else { return false }
            case .month: guard start < now.addingTimeInterval(30 * 86_400) else { return false }
            }
            switch price {
            case .all: break
            case .free: guard event.isFree == true || event.priceMin == 0 else { return false }
            case .upTo20: guard event.isFree == true || (event.priceMin.map { $0 <= 20 } ?? false) else { return false }
            case .upTo50: guard event.isFree == true || (event.priceMin.map { $0 <= 50 } ?? false) else { return false }
            }
            if let genre, !event.genreLabels.contains(genre) { return false }
            if let venue, event.venueName != venue { return false }
            if !text.isEmpty, !event.title.localizedCaseInsensitiveContains(text) { return false }
            return true
        }
        .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var isFiltered: Bool { period != .all || price != .all || genre != nil || venue != nil || !text.isEmpty }

    private func chipRow(_ items: [(String, Bool, () -> Void)]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    Button { withAnimation(.snappy) { items[i].2() } } label: { chip(items[i].0, selected: items[i].1) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, selected: Bool, systemImage: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)), in: .capsule)
    }

    var body: some View {
        List {
            // 07.11.2026: Chips statt Auswahllisten – ein Tipp pro Filter.
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    chipRow(Period.allCases.map { p in (p.rawValue, period == p, { period = p }) })
                    chipRow(Price.allCases.map { p in (p.rawValue, price == p, { price = price == p ? .all : p }) })
                    chipRow(genres.map { g in (g, genre == g, { genre = genre == g ? nil : g }) })
                    HStack {
                        Menu {
                            Button("Alle Spielstätten") { venue = nil }
                            ForEach(venues, id: \.self) { v in Button(v) { venue = v } }
                        } label: {
                            chip(venue ?? "Spielstätte", selected: venue != nil, systemImage: "building.columns")
                        }
                        Spacer()
                        if isFiltered {
                            Button("Zurücksetzen") {
                                withAnimation { period = .all; price = .all; genre = nil; venue = nil; text = "" }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 10)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if results.isEmpty {
                    ContentUnavailableView("Keine passenden Konzerte", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Probiere einen anderen Zeitraum oder weniger Filter."))
                } else {
                    ForEach(results.prefix(200)) { event in
                        NavigationLink(value: event) { ConcertRow(event: event, horizontalPadding: 0) }
                    }
                }
            } header: {
                Text(results.count == 1 ? "1 Konzert" : "\(results.count) Konzerte")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $text, prompt: "Titel enthält …")
        .navigationTitle("Konzerte filtern")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: results.map(\.id))
    }
}
