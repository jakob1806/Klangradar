// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Abos/Zyklen auf der
// Konzertseite, eigene Abo-Seite mit allen Terminen und Abo-Übersicht im Profil.
// Ausgebaut 27.10.2026: "Abos entdecken" (alle Abos je Veranstalter), Abo-Seite
// mit Titelbild und Bildern je Termin, Termine öffnen direkt die Konzertseite
// (unabhängig davon, in welchem Navigationsstapel die Abo-Seite liegt), sichtbare
// Fehlermeldung beim Hinzufügen.
import SwiftUI

/// Kapseln unter den Eckdaten: "Teil von Abo B" → Abo-Seite.
struct EventSubscriptionsRow: View {
    let event: ConcertEvent
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var subscriptions: [ConcertSubscription] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !subscriptions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(subscriptions) { subscription in
                            NavigationLink {
                                SubscriptionDetailView(subscription: subscription, repository: repository,
                                                       contentRepository: contentRepository, currentEventID: event.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "rectangle.stack.badge.person.crop").font(.caption.weight(.semibold))
                                    Text("Teil von \(subscription.name)").font(.footnote.weight(.semibold))
                                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(KlangradarTheme.accent)
                                .background(KlangradarTheme.accent.opacity(0.1), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Zeigt alle Konzerte dieses Abos")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: event.id) { subscriptions = await PlannerAPI.subscriptions(eventID: event.id) }
    }
}

/// Bild in festem Rahmen: scaledToFill darf den Rahmen nicht aufweiten
/// (sonst ragten Titelbilder über den Bildschirmrand hinaus).
private struct FramedImage<Content: View>: View {
    let height: CGFloat
    var cornerRadius: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { content() }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct RemoteCover: View {
    let url: URL?
    var body: some View {
        CachedAsyncImage(url: url, maxPixel: 900) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(colors: [KlangradarTheme.deepInk, KlangradarTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay { Image(systemName: "rectangle.stack.fill").font(.title).foregroundStyle(.white.opacity(0.7)) }
            }
        }
    }
}

struct SubscriptionDetailView: View {
    let subscription: ConcertSubscription
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    var currentEventID: UUID? = nil

    @State private var events: [ConcertEvent] = []
    @State private var isMine = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var upcoming: [ConcertEvent] { events.filter { ($0.startDate ?? .distantFuture) >= Calendar.current.startOfDay(for: .now) } }
    private var past: [ConcertEvent] { events.filter { ($0.startDate ?? .distantFuture) < Calendar.current.startOfDay(for: .now) } }
    private var nextEvent: ConcertEvent? { upcoming.first { $0.id != currentEventID } }

    /// "meist donnerstags · Isarphilharmonie"
    private var pattern: String? {
        let weekdays = upcoming.compactMap { $0.startDate.map { $0.formatted(.dateTime.locale(.klangradarGerman).weekday(.wide)) } }
        let venues = upcoming.map(\.venueName)
        let topDay = Dictionary(grouping: weekdays, by: { $0 }).max { $0.value.count < $1.value.count }
        let topVenue = Dictionary(grouping: venues, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        var parts: [String] = []
        if let topDay, topDay.value.count * 2 > weekdays.count { parts.append("meist \(topDay.key.lowercased())s") }
        if let topVenue { parts.append(topVenue) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                actions
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if isMine {
                    Label("Alle Termine stehen in deinem Saisonplaner.", systemImage: "calendar.badge.checkmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let nextEvent { nextCard(nextEvent) }
                eventList("Alle Termine", upcoming, emptyText: isLoading ? nil : "Für dieses Abo sind keine kommenden Termine bekannt.")
                if !past.isEmpty { eventList("Vergangen", past, emptyText: nil, dimmed: true) }
            }
            .padding(KlangradarTheme.pagePadding)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { KlangradarBackground().ignoresSafeArea() }
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            FramedImage(height: 190, cornerRadius: 24) {
                if let first = upcoming.first ?? events.first {
                    EventArtwork(event: first)
                } else {
                    RemoteCover(url: nil)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("ABO · SAISON \(subscription.season)")
                    .font(.caption2.weight(.bold)).tracking(1.2)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: .capsule)
                    .environment(\.colorScheme, .dark)
                    .foregroundStyle(.white)
                    .padding(12)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(subscription.organizerName.uppercased())
                    .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(KlangradarTheme.accent)
                Text(subscription.name).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                if isLoading {
                    Text("Termine werden geladen …").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(summaryLine).font(.subheadline).foregroundStyle(.secondary)
                }
                if let pattern { Text(pattern).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }

    private var summaryLine: String {
        let count = upcoming.count
        var line = "\(count) \(count == 1 ? "kommendes Konzert" : "kommende Konzerte")"
        if let first = upcoming.first?.startDate, let last = upcoming.last?.startDate, count > 1 {
            let style = Date.FormatStyle.dateTime.locale(.klangradarGerman).day().month(.abbreviated)
            line += " · \(first.formatted(style)) bis \(last.formatted(style.year()))"
        }
        return line
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if SocialStore.shared.isSignedIn {
                Button { Task { await toggleMine() } } label: {
                    Group {
                        if isSaving { ProgressView() } else {
                            Label(isMine ? "In meinem Profil" : "Ich habe dieses Abo", systemImage: isMine ? "checkmark.circle.fill" : "plus.circle")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .foregroundStyle(isMine ? .white : KlangradarTheme.accent)
                    .background(isMine ? KlangradarTheme.accent : KlangradarTheme.accent.opacity(0.1), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityHint(isMine ? "Entfernt das Abo aus deinem Profil" : "Fügt das Abo deinem Profil und Saisonplaner hinzu")
            }
            if let url = subscription.url {
                Link(destination: url) {
                    Label("Abo buchen", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(.primary)
                        .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
                }
            }
        }
    }

    private func detail(_ event: ConcertEvent) -> some View {
        EventDetailView(event: event, repository: repository, contentRepository: contentRepository)
    }

    private func nextCard(_ event: ConcertEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(currentEventID == nil ? "Nächstes Konzert" : "Nächstes Konzert im Abo").font(.title3.bold())
            NavigationLink { detail(event) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    FramedImage(height: 170) { EventArtwork(event: event) }
                    Text(event.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(event.dateLine).font(.subheadline).foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func eventList(_ title: String, _ items: [ConcertEvent], emptyText: String?, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title3.bold()).padding(.bottom, 8)
            if isLoading && !dimmed {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if items.isEmpty, let emptyText {
                Text(emptyText).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NavigationLink { detail(item) } label: { row(item) }
                    .buttonStyle(.plain)
                    .opacity(dimmed ? 0.6 : 1)
                if index < items.count - 1 { Divider().padding(.leading, 76) }
            }
        }
    }

    private func row(_ item: ConcertEvent) -> some View {
        HStack(spacing: 12) {
            EventArtwork(event: item)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottom) {
                    Text(item.startDate.map { $0.formatted(.dateTime.locale(.klangradarGerman).day().month(.abbreviated)) } ?? "–")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .background(.black.opacity(0.55))
                        .clipShape(.rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(item.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.id == currentEventID {
                Text("Dieses").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(KlangradarTheme.accent.opacity(0.12), in: .capsule).foregroundStyle(KlangradarTheme.accent)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func load() async {
        defer { isLoading = false }
        guard let overview = await PlannerAPI.overview(subscription.id) else { return }
        isMine = overview.isMine
        let loaded = (try? await repository.events(ids: overview.eventIDs)) ?? []
        let enriched = (try? await repository.enrichingImages(in: loaded)) ?? loaded
        events = enriched.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private func toggleMine() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await PlannerAPI.setMine(subscription.id, !isMine)
            isMine.toggle()
            Haptics.confirm()
            NotificationCenter.default.post(name: .subscriptionsChanged, object: nil)
        } catch {
            errorMessage = "Das hat nicht geklappt. Bitte versuch es gleich noch einmal."
        }
    }
}

extension Notification.Name {
    static let subscriptionsChanged = Notification.Name("klangradar.subscriptionsChanged")
}

/// "Abos entdecken": alle Abos mit kommenden Terminen, nach Veranstalter.
struct SubscriptionCatalogView: View {
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    var cityID: UUID?

    @State private var entries: [SubscriptionCatalogEntry] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var onlyMine = false

    private var filtered: [SubscriptionCatalogEntry] {
        entries.filter { entry in
            (!onlyMine || entry.isMine)
                && (query.isEmpty || "\(entry.subscription.name) \(entry.subscription.organizerName) \(entry.venueName ?? "")".localizedCaseInsensitiveContains(query))
        }
    }

    private var groups: [(organizer: String, entries: [SubscriptionCatalogEntry])] {
        Dictionary(grouping: filtered, by: \.subscription.organizerName)
            .map { ($0.key, $0.value.sorted { ($0.nextStart ?? .distantFuture) < ($1.nextStart ?? .distantFuture) }) }
            .sorted { $0.organizer < $1.organizer }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                Text("Feste Plätze, ganze Saison: Hier findest du alle Abos und Konzertreihen, die Klangradar kennt. Tippe auf ein Abo, um alle Termine zu sehen und es deinem Profil hinzuzufügen.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if SocialStore.shared.isSignedIn && entries.contains(where: \.isMine) {
                    Picker("Anzeigen", selection: $onlyMine) {
                        Text("Alle Abos").tag(false)
                        Text("Meine Abos").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if groups.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Noch keine Abos" : "Keine Treffer",
                                           systemImage: "rectangle.stack",
                                           description: Text(query.isEmpty ? "Für diese Stadt sind noch keine Abos mit kommenden Terminen bekannt." : "Versuch es mit einem anderen Namen."))
                }
                ForEach(groups, id: \.organizer) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.organizer).font(.title3.bold())
                            Spacer()
                            Text("\(group.entries.count) \(group.entries.count == 1 ? "Abo" : "Abos")").font(.footnote).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(group.entries) { entry in
                                    NavigationLink {
                                        SubscriptionDetailView(subscription: entry.subscription, repository: repository, contentRepository: contentRepository)
                                    } label: { card(entry) }
                                    .buttonStyle(.plain)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.viewAligned)
                    }
                }
            }
            .padding(KlangradarTheme.pagePadding)
        }
        .background { KlangradarBackground().ignoresSafeArea() }
        .navigationTitle("Abos entdecken")
        .searchable(text: $query, prompt: "Abo, Orchester oder Saal")
        .task { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionsChanged)) { _ in Task { await load() } }
    }

    private func card(_ entry: SubscriptionCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FramedImage(height: 120, cornerRadius: 18) { RemoteCover(url: entry.imageURL) }
                .overlay(alignment: .topTrailing) {
                    if entry.isMine {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3).foregroundStyle(.white, KlangradarTheme.accent)
                            .padding(8)
                            .accessibilityLabel("In deinem Profil")
                    }
                }
            Text(entry.subscription.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                .frame(height: 44, alignment: .topLeading)
            Text("\(entry.upcoming) \(entry.upcoming == 1 ? "Konzert" : "Konzerte")\(entry.nextStart.map { " · ab \($0.formatted(.dateTime.locale(.klangradarGerman).day().month(.abbreviated)))" } ?? "")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let venue = entry.venueName {
                Text(venue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 210)
        .contentShape(.rect)
    }

    private func load() async {
        defer { isLoading = false }
        entries = await PlannerAPI.catalog(cityID: cityID)
    }
}

/// Profil/Mein Klangradar: eigene Abos, erkannte Abo-Kandidaten und Einstieg
/// in "Abos entdecken".
struct MySubscriptionsSection: View {
    let repository: any EventRepository
    let contentRepository: any ContentRepository
    var cityID: UUID?
    @State private var mine: [ConcertSubscription] = []
    @State private var suggestions: [SubscriptionSuggestion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meine Abos").font(.title3.bold())
            ForEach(mine) { subscription in
                NavigationLink { SubscriptionDetailView(subscription: subscription, repository: repository, contentRepository: contentRepository) } label: {
                    row(icon: "rectangle.stack.fill", title: subscription.name, subtitle: "\(subscription.organizerName) · Saison \(subscription.season)")
                }
                .buttonStyle(.plain)
            }
            ForEach(suggestions) { suggestion in
                NavigationLink { SubscriptionDetailView(subscription: suggestion.subscription, repository: repository, contentRepository: contentRepository) } label: {
                    row(icon: "sparkles", title: "Gibt es als Abo: \(suggestion.subscription.name)",
                        subtitle: "\(suggestion.matched) von \(suggestion.total) Konzerten hast du dir gemerkt · \(suggestion.subscription.organizerName)")
                }
                .buttonStyle(.plain)
            }
            NavigationLink { SubscriptionCatalogView(repository: repository, contentRepository: contentRepository, cityID: cityID) } label: {
                row(icon: "magnifyingglass", title: mine.isEmpty ? "Abo hinzufügen" : "Alle Abos entdecken",
                    subtitle: mine.isEmpty ? "Du hast ein Abo? Füge es hinzu – die Termine landen im Saisonplaner." : "Abos und Konzertreihen aller Veranstalter")
            }
            .buttonStyle(.plain)
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .subscriptionsChanged)) { _ in Task { await load() } }
    }

    private func load() async {
        async let ownTask = PlannerAPI.mySubscriptions()
        async let suggestionsTask = PlannerAPI.suggestions()
        mine = await ownTask
        suggestions = await suggestionsTask
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.headline).foregroundStyle(KlangradarTheme.accent)
                .frame(width: 40, height: 40)
                .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
