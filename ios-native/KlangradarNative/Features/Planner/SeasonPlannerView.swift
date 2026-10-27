// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Saisonplaner –
// geplante, gemerkte und Abo-Konzerte über die nächsten Monate, mit
// Überschneidungen und passenden Vorschlägen je Monat.
import SwiftUI

struct SeasonPlannerView: View {
    let repository: any EventRepository
    @EnvironmentObject private var favorites: FavoriteStore
    @EnvironmentObject private var cityStore: CityStore

    private struct Item: Identifiable {
        let event: ConcertEvent
        var planned = false
        var saved = false
        var subscriptions: [ConcertSubscription] = []
        var id: UUID { event.id }
    }

    private struct Month: Identifiable {
        let start: Date
        var items: [Item]
        var suggestions: [ConcertEvent]
        var id: Date { start }
    }

    @State private var months: [Month] = []
    @State private var isLoading = true
    @State private var selectedMonth: Date?

    private static let horizonMonths = 9

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if isLoading {
                        ProgressView("Saison wird geplant …").frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        monthStrip(proxy)
                        ForEach(months) { month in
                            monthSection(month).id(month.start)
                        }
                    }
                }
                .padding(KlangradarTheme.pagePadding)
            }
        }
        .background { KlangradarBackground().ignoresSafeArea() }
        .navigationTitle("Saisonplaner")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        let all = months.flatMap(\.items)
        return VStack(alignment: .leading, spacing: 6) {
            Text("DEINE SAISON").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(KlangradarTheme.accent)
            Text("\(all.count) Konzerte in den nächsten \(Self.horizonMonths) Monaten").font(.title2.bold())
            let conflicts = months.reduce(0) { $0 + conflictDays(in: $1).count }
            Text(conflicts > 0 ? "\(conflicts) \(conflicts == 1 ? "Tag" : "Tage") mit Überschneidung – prüf, welches Konzert du nimmst." : "Gemerkt, geplant und aus deinen Abos – ohne Überschneidungen.")
                .font(.subheadline).foregroundStyle(conflicts > 0 ? .orange : .secondary)
        }
    }

    /// Monatsleiste: Balkenhöhe = Anzahl eigener Konzerte, antippen springt hin.
    private func monthStrip(_ proxy: ScrollViewProxy) -> some View {
        let maxCount = max(months.map(\.items.count).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(months) { month in
                Button {
                    selectedMonth = month.start
                    withAnimation(.snappy) { proxy.scrollTo(month.start, anchor: .top) }
                    Haptics.light()
                } label: {
                    VStack(spacing: 6) {
                        Text("\(month.items.count)").font(.caption2.weight(.bold)).foregroundStyle(month.items.isEmpty ? .tertiary : .primary)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(month.items.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.15)) : AnyShapeStyle(KlangradarTheme.accent.gradient))
                            .frame(height: 12 + 56 * CGFloat(month.items.count) / CGFloat(maxCount))
                        Text(month.start.formatted(.dateTime.locale(.klangradarGerman).month(.abbreviated))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(month.start.formatted(.dateTime.locale(.klangradarGerman).month(.wide))): \(month.items.count) Konzerte")
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.7), in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func monthSection(_ month: Month) -> some View {
        let conflicts = conflictDays(in: month)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.start.formatted(.dateTime.locale(.klangradarGerman).month(.wide).year())).font(.title3.bold())
                Spacer()
                Text(month.items.isEmpty ? "frei" : "\(month.items.count) geplant").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(month.items) { item in
                let day = Calendar.current.startOfDay(for: item.event.startDate ?? .distantPast)
                NavigationLink(value: item.event) { row(item, conflict: conflicts.contains(day)) }
                    .buttonStyle(.plain)
            }
            if !month.suggestions.isEmpty {
                Text(month.items.isEmpty ? "Noch nichts geplant – vielleicht das:" : "Passt auch noch:")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(month.suggestions) { event in
                            NavigationLink(value: event) {
                                VStack(alignment: .leading, spacing: 6) {
                                    EventArtwork(event: event).frame(width: 160, height: 96).clipped().clipShape(.rect(cornerRadius: 14))
                                    Text(event.title).font(.footnote.weight(.semibold)).lineLimit(2)
                                    Text(event.dateLine).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 160, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func row(_ item: Item, conflict: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(item.event.startDate.map { $0.formatted(.dateTime.locale(.klangradarGerman).day()) } ?? "–").font(.title3.bold())
                Text(item.event.startDate.map { $0.formatted(.dateTime.locale(.klangradarGerman).weekday(.abbreviated)) } ?? "").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(item.event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if conflict { badge("Überschneidung", .orange) }
                    if item.planned { badge("Geplant", KlangradarTheme.accent) }
                    if item.saved && !item.planned { badge("Gemerkt", .pink) }
                    ForEach(item.subscriptions) { badge($0.name, .teal) }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground).opacity(0.85), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            if conflict { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.orange.opacity(0.6), lineWidth: 1.5) }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color).background(color.opacity(0.12), in: .capsule)
    }

    private func conflictDays(in month: Month) -> Set<Date> {
        let days = month.items.compactMap { $0.event.startDate.map { Calendar.current.startOfDay(for: $0) } }
        return Set(Dictionary(grouping: days, by: { $0 }).filter { $0.value.count > 1 }.keys)
    }

    private func load() async {
        defer { isLoading = false }
        async let plannedTask = PlannerAPI.plannedEventIDs()
        async let subscriptionTask = PlannerAPI.subscriptionEventIDs()
        async let suggestionsTask: [ConcertEvent] = (try? await SocialStore.shared.repository?.recommendedEvents(limit: 40, cityID: cityStore.selectedCity?.id, token: SocialStore.shared.token)) ?? []
        let planned = await plannedTask
        let bySubscription = await subscriptionTask
        let ids = Array(planned.union(favorites.ids).union(bySubscription.keys))
        let loaded = (try? await repository.events(ids: ids)) ?? []
        let suggestions = await suggestionsTask
        var seen = Set<UUID>()
        let combined = (loaded + suggestions).filter { seen.insert($0.id).inserted }
        let enrichedByID = Dictionary(((try? await repository.enrichingImages(in: combined)) ?? combined).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let calendar = Calendar.current
        let firstMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
        var result = (0..<Self.horizonMonths).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: firstMonth).map { Month(start: $0, items: [], suggestions: []) }
        }
        func monthIndex(_ date: Date?) -> Int? {
            guard let date else { return nil }
            return result.firstIndex { calendar.isDate($0.start, equalTo: date, toGranularity: .month) }
        }
        for event in loaded {
            guard let index = monthIndex(event.startDate) else { continue }
            result[index].items.append(Item(event: enrichedByID[event.id] ?? event, planned: planned.contains(event.id), saved: favorites.ids.contains(event.id), subscriptions: bySubscription[event.id] ?? []))
        }
        let mine = Set(loaded.map(\.id))
        for event in suggestions where !mine.contains(event.id) {
            guard let index = monthIndex(event.startDate), result[index].suggestions.count < 3 else { continue }
            // Keine Vorschläge an Tagen, an denen schon ein eigenes Konzert liegt.
            let day = calendar.startOfDay(for: event.startDate ?? .now)
            guard !result[index].items.contains(where: { calendar.isDate($0.event.startDate ?? .distantPast, inSameDayAs: day) }) else { continue }
            result[index].suggestions.append(enrichedByID[event.id] ?? event)
        }
        for index in result.indices {
            result[index].items.sort { ($0.event.startDate ?? .distantFuture) < ($1.event.startDate ?? .distantFuture) }
        }
        months = result
    }
}
