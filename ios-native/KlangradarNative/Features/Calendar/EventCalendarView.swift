import SwiftUI

struct EventCalendarView: View {
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    let auth: AuthStore?
    let userRepository: UserRepository?
    // Für Marketing-Screenshots (siehe MarketingAppShellView): Kalender
    // bleibt dort bewusst eine reine Live-Ansicht ohne Werkzeug -- die echte
    // Multiauswahl/Gruppen-Funktion bleibt im normalen Nutzerfluss unverändert.
    var hidesSelectionUI = false
    @EnvironmentObject private var cityStore: CityStore
    @State private var selectedDate = Date.now
    @State private var visibleMonth = Date.now
    @State private var events: [ConcertEvent] = []

    // Nutzerwunsch: "Multiauswahl bei Veranstaltungen soll die Option
    // ergeben, daraus eine Gruppe zu erstellen" — nutzt dieselbe
    // favorite_lists/favorite_list_items-Infrastruktur wie "Meine Listen"
    // im Profil (UserRepository.createEventList/replaceEvents), damit eine
    // hier erstellte Gruppe dort direkt sichtbar/bearbeitbar ist.
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showsNamePrompt = false
    @State private var groupName = ""
    @State private var isCreatingGroup = false
    @State private var creationError: String?
    @State private var createdListName: String?

    private var selectedEvents: [ConcertEvent] {
        events.filter { $0.startDate.map { KlangradarDateTime.calendar.isDate($0, inSameDayAs: selectedDate) } ?? false }
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

                    HStack {
                        Text(KlangradarDateTime.string(selectedDate, format: "EEEE, d. MMMM"))
                            .font(.title2.bold())
                        Spacer()
                        if !hidesSelectionUI, auth?.userID != nil, !selectedEvents.isEmpty {
                            Button(isSelecting ? "Fertig" : "Auswählen") {
                                isSelecting.toggle()
                                if !isSelecting { selectedIDs.removeAll() }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }

                    if selectedEvents.isEmpty {
                        ContentUnavailableView("Keine Konzerte", systemImage: "calendar.badge.minus", description: Text("Für diesen Tag sind keine Veranstaltungen verfügbar."))
                    } else {
                        LiquidGlassSurface(cornerRadius: 24) {
                            VStack(spacing: 0) {
                                ForEach(Array(selectedEvents.enumerated()), id: \.element.id) { index, event in
                                    if isSelecting {
                                        Button {
                                            if selectedIDs.contains(event.id) { selectedIDs.remove(event.id) }
                                            else { selectedIDs.insert(event.id) }
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: selectedIDs.contains(event.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.title3)
                                                    .foregroundStyle(selectedIDs.contains(event.id) ? KlangradarTheme.accent : Color.secondary)
                                                CalendarEventRow(event: event)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink(value: event) { CalendarEventRow(event: event) }
                                            .buttonStyle(.plain)
                                    }
                                    if index < selectedEvents.count - 1 { Divider().padding(.leading, 78) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(KlangradarTheme.pagePadding)
                .padding(.bottom, isSelecting && !selectedIDs.isEmpty ? 140 : 100)
                .frame(maxWidth: .infinity)
            }
            .background { KlangradarBackground().ignoresSafeArea() }
            .safeAreaInset(edge: .bottom) {
                if isSelecting, !selectedIDs.isEmpty {
                    Button {
                        groupName = ""
                        showsNamePrompt = true
                    } label: {
                        Label("Gruppe erstellen (\(selectedIDs.count))", systemImage: "rectangle.stack.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(KlangradarTheme.pagePadding)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .modifier(HiddenScrollEdgeNavigationBar())
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        CityCompactMenu(cityStore: cityStore)
                    }
                }
            }
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: repository, contentRepository: contentRepository) }
            .task { await loadEvents() }
            .onChange(of: cityStore.selectedCity) { _, _ in
                Task { await loadEvents() }
            }
            .alert("Neue Gruppe", isPresented: $showsNamePrompt) {
                TextField("Name der Gruppe", text: $groupName)
                Button("Abbrechen", role: .cancel) {}
                Button("Erstellen") { Task { await createGroup() } }
            } message: {
                Text("\(selectedIDs.count) Veranstaltungen werden in die neue Gruppe aufgenommen.")
            }
            .alert("Gruppe konnte nicht erstellt werden", isPresented: Binding(get: { creationError != nil }, set: { if !$0 { creationError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(creationError ?? "")
            }
            .alert("Gruppe erstellt", isPresented: Binding(get: { createdListName != nil }, set: { if !$0 { createdListName = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("„\(createdListName ?? "")“ ist jetzt unter Profil → Meine Listen verfügbar.")
            }
        }
        .environment(\.locale, Locale(identifier: "de_DE"))
    }

    private func loadEvents() async {
        let basic = (try? await repository.allUpcomingEvents(regionID: cityStore.selectedCity?.id)) ?? []
        events = basic
        if let enriched = try? await repository.enrichingImages(in: basic) { events = enriched }
    }

    private func createGroup() async {
        guard let userRepository, let auth, let userID = auth.userID, let token = auth.accessToken else { return }
        isCreatingGroup = true
        defer { isCreatingGroup = false }
        do {
            guard let list = try await userRepository.createEventList(name: groupName, userID: userID, token: token) else {
                creationError = "Bitte einen Namen eingeben."
                return
            }
            try await userRepository.replaceEvents(in: list.id, selected: selectedIDs, previous: [], token: token)
            Haptics.confirm() // Generated by Claude Code — beim finalen Speichern, nicht beim Öffnen des Dialogs
            createdListName = list.name
            isSelecting = false
            selectedIDs.removeAll()
        } catch {
            creationError = error.localizedDescription
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
                Text(event.venueName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(13)
        .contentShape(.rect)
    }
}
