import SwiftUI

struct EventCalendarView: View {
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    let auth: AuthStore?
    let userRepository: UserRepository?
    @EnvironmentObject private var cityStore: CityStore
    @ObservedObject private var promoted = PromotedEventsStore.shared
    /// "Alle Städte" gilt nur im Kalender; eine konkrete Stadt gilt überall.
    @State private var showsAllCities = false
    private var regionID: UUID? { showsAllCities ? nil : cityStore.selectedCity?.id }
    @State private var selectedDate = Date.now
    @State private var visibleMonth = Date.now
    @State private var events: [ConcertEvent] = []
    @State private var loadFailed = false
    /// Bereits geladene Monate (pro Stadt) — beim Zurückblättern oder
    /// Tab-Wechsel nicht erneut laden.
    @State private var monthCache: [String: [ConcertEvent]] = [:]
    /// Monat / Woche / Tag (Nutzerwunsch 25.10.2026).
    @State private var mode: CalendarMode = .month

    enum CalendarMode: String, CaseIterable, Identifiable {
        case month = "Monat", week = "Woche", day = "Tag"
        var id: String { rawValue }
    }

    private var weekCalendar: Calendar {
        var value = KlangradarDateTime.calendar; value.firstWeekday = 2; return value
    }

    /// Geladener Zeitraum: Monat (bzw. Woche über Monatsgrenzen hinweg).
    private var monthInterval: DateInterval {
        let month = KlangradarDateTime.calendar.dateInterval(of: .month, for: visibleMonth) ?? DateInterval(start: .now, duration: 31 * 86_400)
        guard mode != .month, let week = weekCalendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return month }
        return DateInterval(start: min(month.start, week.start), end: max(month.end, week.end))
    }
    private var loadKey: String { "\(regionID?.uuidString ?? "all")|\(Int(monthInterval.start.timeIntervalSince1970))|\(Int(monthInterval.end.timeIntervalSince1970))" }

    private var weekDays: [Date] {
        guard let start = weekCalendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return [] }
        return (0..<7).compactMap { weekCalendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func events(on day: Date) -> [ConcertEvent] {
        events.filter { $0.startDate.map { KlangradarDateTime.calendar.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private func shift(days: Int) {
        guard let date = KlangradarDateTime.calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        Haptics.light()
        selectedDate = date
        visibleMonth = date
    }

    private var selectedEvents: [ConcertEvent] {
        // Beworbene Events (Platzierung "standard") stehen in ihrer Tagesliste vorn.
        let day = events.filter { $0.startDate.map { KlangradarDateTime.calendar.isDate($0, inSameDayAs: selectedDate) } ?? false }
        return promoted.boosting(day, placement: "standard", regionID: regionID, maxPromoted: 3) { promotedEvent in
            day.contains { $0.id == promotedEvent.id }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Ansicht", selection: $mode.animation(.snappy)) {
                        ForEach(CalendarMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .month:
                        MonthEventCalendar(
                            visibleMonth: $visibleMonth,
                            selectedDate: $selectedDate,
                            eventDates: events.compactMap(\.startDate)
                        )
                        dayHeader
                        dayList(selectedEvents)
                    case .week:
                        weekStrip
                        if loadFailed && events.isEmpty {
                            LoadFailureView { Task { await loadEvents() } }
                        } else {
                            ForEach(weekDays, id: \.self) { day in
                                let list = events(on: day)
                                if !list.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(KlangradarDateTime.string(day, format: "EEEE, d. MMMM"))
                                            .font(.headline)
                                            .foregroundStyle(KlangradarDateTime.calendar.isDateInToday(day) ? KlangradarTheme.accent : .primary)
                                        eventGroup(list)
                                    }
                                }
                            }
                            if weekDays.allSatisfy({ events(on: $0).isEmpty }) {
                                ContentUnavailableView("Keine Konzerte", systemImage: "calendar.badge.minus", description: Text("In dieser Woche sind keine Veranstaltungen verfügbar."))
                            }
                        }
                    case .day:
                        HStack {
                            Button("Vorheriger Tag", systemImage: "chevron.left") { shift(days: -1) }.labelStyle(.iconOnly)
                            Spacer()
                            VStack(spacing: 2) {
                                Text(KlangradarDateTime.string(selectedDate, format: "EEEE")).font(.subheadline).foregroundStyle(.secondary)
                                Text(KlangradarDateTime.string(selectedDate, format: "d. MMMM yyyy")).font(.title2.bold())
                            }
                            Spacer()
                            Button("Nächster Tag", systemImage: "chevron.right") { shift(days: 1) }.labelStyle(.iconOnly)
                        }
                        .font(.title3.weight(.semibold))
                        if loadFailed && events.isEmpty {
                            LoadFailureView { Task { await loadEvents() } }
                        } else if selectedEvents.isEmpty {
                            ContentUnavailableView("Keine Konzerte", systemImage: "calendar.badge.minus", description: Text("Für diesen Tag sind keine Veranstaltungen verfügbar."))
                        } else {
                            DayTimeline(events: selectedEvents.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) })
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(KlangradarTheme.pagePadding)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
            .background { KlangradarBackground().ignoresSafeArea() }
            .navigationTitle("Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(HiddenScrollEdgeNavigationBar())
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore, allCitiesSelection: $showsAllCities)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore, allCitiesSelection: $showsAllCities)
                    }
                }
            }
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: repository, contentRepository: contentRepository) }
            .navigationDestination(for: EntityRoute.self) { EntityDetailView(route: $0, repository: contentRepository) }
            // .task(id:) bricht eine laufende Ladung bei Stadtwechsel ab, sodass
            // eine späte Antwort der alten Stadt die neue nicht überschreibt.
            .task(id: loadKey) { await loadEvents() }
            .refreshable { await loadEvents(force: true) }
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
    }

    private var dayHeader: some View {
        Text(KlangradarDateTime.string(selectedDate, format: "EEEE, d. MMMM")).font(.title2.bold())
    }

    @ViewBuilder private func dayList(_ list: [ConcertEvent]) -> some View {
        if loadFailed && events.isEmpty {
            LoadFailureView { Task { await loadEvents() } }
        } else if list.isEmpty {
            ContentUnavailableView("Keine Konzerte", systemImage: "calendar.badge.minus", description: Text("Für diesen Tag sind keine Veranstaltungen verfügbar."))
        } else {
            eventGroup(list)
        }
    }

    private func eventGroup(_ list: [ConcertEvent]) -> some View {
        LiquidGlassSurface(cornerRadius: 24) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, event in
                    NavigationLink(value: event) { CalendarEventRow(event: event) }
                        .buttonStyle(.plain)
                    if index < list.count - 1 { Divider().padding(.leading, 78) }
                }
            }
        }
    }

    /// Woche: sieben Tage nebeneinander mit Anzahl, Pfeile blättern wochenweise.
    private var weekStrip: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Vorherige Woche", systemImage: "chevron.left") { shift(days: -7) }.labelStyle(.iconOnly)
                Spacer()
                if let first = weekDays.first, let last = weekDays.last {
                    Text("\(KlangradarDateTime.string(first, format: "d. MMM")) – \(KlangradarDateTime.string(last, format: "d. MMM yyyy"))").font(.headline)
                }
                Spacer()
                Button("Nächste Woche", systemImage: "chevron.right") { shift(days: 7) }.labelStyle(.iconOnly)
            }
            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    let count = events(on: day).count
                    let isSelected = KlangradarDateTime.calendar.isDate(day, inSameDayAs: selectedDate)
                    Button {
                        Haptics.light()
                        selectedDate = day
                        mode = .day
                    } label: {
                        VStack(spacing: 4) {
                            Text(KlangradarDateTime.string(day, format: "EE")).font(.caption2.weight(.semibold)).foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                            Text(KlangradarDateTime.string(day, format: "d")).font(.headline.monospacedDigit())
                            Text(count > 0 ? "\(count)" : "–").font(.caption2.weight(.bold)).foregroundStyle(isSelected ? .white : (count > 0 ? KlangradarTheme.accent : .secondary))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(isSelected ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)), in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(KlangradarDateTime.string(day, format: "EEEE, d. MMMM")), \(count) Konzerte")
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    /// Lädt nur den sichtbaren Monat statt aller (~1500) kommenden Konzerte.
    private func loadEvents(force: Bool = false) async {
        await cityStore.waitUntilResolved()
        let key = loadKey
        if !force, let cached = monthCache[key] {
            events = cached
            return
        }
        do {
            let interval = monthInterval
            let basic = try await repository.events(from: interval.start, to: interval.end, regionID: regionID)
            try Task.checkCancellation()
            loadFailed = false
            events = basic
            if let enriched = try? await repository.enrichingImages(in: basic), !Task.isCancelled { events = enriched }
            monthCache[key] = events
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }
}

private struct MonthEventCalendar: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    let eventDates: [Date]
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "de_DE"); value.firstWeekday = 2; return value
    }()
    private let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let range = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Vorheriger Monat", systemImage: "chevron.left") { changeMonth(-1) }.labelStyle(.iconOnly)
                Spacer()
                Text(KlangradarDateTime.string(visibleMonth, format: "MMMM yyyy")).font(.headline)
                Spacer()
                Button("Nächster Monat", systemImage: "chevron.right") { changeMonth(1) }.labelStyle(.iconOnly)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 9) {
                ForEach(weekdays, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(.secondary) }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button {
                            // Generated by Claude Code — leichtes Feedback
                            // beim Tageswechsel, etwas deutlicher, wenn an
                            // diesem Tag Veranstaltungen liegen.
                            hasEvent(on: date) ? Haptics.confirm() : Haptics.light()
                            selectedDate = date
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(calendar.component(.day, from: date))").frame(width: 34, height: 30).background(calendar.isDate(date, inSameDayAs: selectedDate) ? KlangradarTheme.accent : .clear, in: .circle).foregroundStyle(calendar.isDate(date, inSameDayAs: selectedDate) ? .white : .primary)
                                Circle().fill(hasEvent(on: date) ? KlangradarTheme.accent : .clear).frame(width: 5, height: 5)
                            }
                        }.buttonStyle(.plain)
                    } else { Color.clear.frame(height: 38) }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }

    private func hasEvent(on date: Date) -> Bool { eventDates.contains { calendar.isDate($0, inSameDayAs: date) } }
    private func changeMonth(_ offset: Int) { if let date = calendar.date(byAdding: .month, value: offset, to: visibleMonth) { visibleMonth = date } }
}

private struct CalendarEventRow: View {
    let event: ConcertEvent
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            EventArtwork(event: event)
                .frame(width: 52, height: 52)
                .clipped()
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(event.startDate.map { KlangradarDateTime.string($0, format: "HH:mm") } ?? "–")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(KlangradarTheme.accent)
                Text(event.title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text([event.venueName, event.priceLabel].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(13)
        .contentShape(.rect)
    }
}

/// Tagesansicht als Zeitleiste: Uhrzeit links, Konzerte rechts.
private struct DayTimeline: View {
    let events: [ConcertEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Text(event.startDate.map { KlangradarDateTime.string($0, format: "HH:mm") } ?? "–")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(KlangradarTheme.accent)
                            .frame(width: 52, alignment: .trailing)
                    }
                    VStack(spacing: 0) {
                        Circle().fill(KlangradarTheme.accent).frame(width: 9, height: 9).padding(.top, 5)
                        if index < events.count - 1 {
                            Rectangle().fill(KlangradarTheme.accent.opacity(0.2)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    NavigationLink(value: event) {
                        HStack(spacing: 12) {
                            EventArtwork(event: event)
                                .frame(width: 56, height: 56)
                                .clipped()
                                .clipShape(.rect(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                Text([event.venueName, event.priceLabel].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 18)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
