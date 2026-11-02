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

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Preis", selection: $price) {
                    ForEach(Price.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Genre", selection: $genre) {
                    Text("Alle Genres").tag(String?.none)
                    ForEach(genres, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Spielstätte", selection: $venue) {
                    Text("Alle Spielstätten").tag(String?.none)
                    ForEach(venues, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                if isFiltered {
                    Button("Filter zurücksetzen", role: .destructive) {
                        withAnimation { period = .all; price = .all; genre = nil; venue = nil; text = "" }
                    }
                }
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
