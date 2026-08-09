import SwiftUI

struct EventCalendarView: View {
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var selectedDate = Date.now
    @State private var visibleMonth = Date.now
    @State private var events: [ConcertEvent] = []

    private var selectedEvents: [ConcertEvent] {
        events.filter { $0.startDate.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } ?? false }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MonthEventCalendar(
                        visibleMonth: $visibleMonth,
                        selectedDate: $selectedDate,
                        eventDates: events.compactMap(\.startDate)
                    )

                    Text(selectedDate.formatted(.dateTime.locale(Locale(identifier: "de_DE")).weekday(.wide).day().month(.wide)))
                        .font(.title2.bold())

                    if selectedEvents.isEmpty {
                        ContentUnavailableView("Keine Konzerte", systemImage: "calendar.badge.minus", description: Text("Für diesen Tag sind keine Veranstaltungen verfügbar."))
                    } else {
                        LiquidGlassSurface(cornerRadius: 24) {
                            VStack(spacing: 0) {
                                ForEach(Array(selectedEvents.enumerated()), id: \.element.id) { index, event in
                                    NavigationLink(value: event) { CalendarEventRow(event: event) }
                                        .buttonStyle(.plain)
                                    if index < selectedEvents.count - 1 { Divider().padding(.leading, 78) }
                                }
                            }
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
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: repository, contentRepository: contentRepository) }
            .task {
                let basic = (try? await repository.allUpcomingEvents()) ?? []
                events = basic
                if let enriched = try? await repository.enrichingImages(in: basic) { events = enriched }
            }
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
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
                Text(visibleMonth.formatted(.dateTime.locale(Locale(identifier: "de_DE")).month(.wide).year())).font(.headline)
                Spacer()
                Button("Nächster Monat", systemImage: "chevron.right") { changeMonth(1) }.labelStyle(.iconOnly)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 9) {
                ForEach(weekdays, id: \.self) { Text($0).font(.caption.bold()).foregroundStyle(.secondary) }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button { selectedDate = date } label: {
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
                Text(event.startDate?.formatted(.dateTime.hour().minute()) ?? "–")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(KlangradarTheme.accent)
                Text(event.title).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(event.venueName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(13)
        .contentShape(.rect)
    }
}
