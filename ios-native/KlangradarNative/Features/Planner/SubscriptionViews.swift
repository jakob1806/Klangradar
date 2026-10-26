// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Abos/Zyklen auf der
// Konzertseite, eigene Abo-Seite mit allen Terminen und Abo-Übersicht im Profil.
import SwiftUI

/// Kapseln unter den Eckdaten: "Abo B · Münchner Philharmoniker" → Abo-Seite.
struct EventSubscriptionsRow: View {
    let event: ConcertEvent
    let repository: any EventRepository
    @State private var subscriptions: [ConcertSubscription] = []

    var body: some View {
        Group {
            if !subscriptions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(subscriptions) { subscription in
                            NavigationLink {
                                SubscriptionDetailView(subscription: subscription, repository: repository, currentEventID: event.id)
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

struct SubscriptionDetailView: View {
    let subscription: ConcertSubscription
    let repository: any EventRepository
    var currentEventID: UUID? = nil

    @State private var events: [ConcertEvent] = []
    @State private var isMine = false
    @State private var isLoading = true
    @State private var isSaving = false

    private var nextEvent: ConcertEvent? {
        events.first { $0.id != currentEventID && ($0.startDate ?? .distantPast) >= .now }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(subscription.organizerName.uppercased())
                        .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(KlangradarTheme.accent)
                    Text(subscription.name).font(.largeTitle.bold())
                    Text("Saison \(subscription.season) · \(events.count) \(events.count == 1 ? "Konzert" : "Konzerte")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    if SocialStore.shared.isSignedIn {
                        Button { Task { await toggleMine() } } label: {
                            Label(isMine ? "Mein Abo" : "Ich habe dieses Abo", systemImage: isMine ? "checkmark.circle.fill" : "plus.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .foregroundStyle(isMine ? .white : KlangradarTheme.accent)
                                .background(isMine ? KlangradarTheme.accent : KlangradarTheme.accent.opacity(0.1), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                    if let url = subscription.url {
                        Link(destination: url) {
                            Label("Abo buchen", systemImage: "arrow.up.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .foregroundStyle(.primary)
                                .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
                        }
                    }
                }
                if isMine {
                    Text("Alle Termine dieses Abos stehen jetzt in deinem Saisonplaner.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if let nextEvent {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(currentEventID == nil ? "Nächstes Konzert" : "Nächstes Konzert im Abo").font(.title3.bold())
                        NavigationLink(value: nextEvent) {
                            VStack(alignment: .leading, spacing: 10) {
                                EventArtwork(event: nextEvent)
                                    .frame(height: 170).frame(maxWidth: .infinity)
                                    .clipped().clipShape(.rect(cornerRadius: 20))
                                Text(nextEvent.title).font(.headline).lineLimit(2)
                                Text(nextEvent.dateLine).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Alle Termine").font(.title3.bold()).padding(.bottom, 8)
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if events.isEmpty {
                        Text("Für dieses Abo sind keine kommenden Termine bekannt.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            HStack(spacing: 12) {
                                VStack(spacing: 0) {
                                    Text(item.startDate.map { $0.formatted(.dateTime.day()) } ?? "–").font(.title3.bold())
                                    Text(item.startDate.map { $0.formatted(.dateTime.month(.abbreviated)) } ?? "").font(.caption2.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                                }
                                .frame(width: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(item.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if item.id == currentEventID {
                                    Text("Dieses").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(KlangradarTheme.accent.opacity(0.12), in: .capsule).foregroundStyle(KlangradarTheme.accent)
                                }
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if index < events.count - 1 { Divider() }
                    }
                }
            }
            .padding(KlangradarTheme.pagePadding)
        }
        .background { KlangradarBackground().ignoresSafeArea() }
        .navigationTitle("Abo")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
        defer { isSaving = false }
        do {
            try await PlannerAPI.setMine(subscription.id, !isMine)
            isMine.toggle()
            Haptics.confirm()
        } catch {}
    }
}

/// Profil/Mein Klangradar: eigene Abos und erkannte Abo-Kandidaten.
struct MySubscriptionsSection: View {
    let repository: any EventRepository
    @State private var mine: [ConcertSubscription] = []
    @State private var suggestions: [SubscriptionSuggestion] = []

    var body: some View {
        Group {
            if !mine.isEmpty || !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Meine Abos").font(.title3.bold())
                    ForEach(mine) { subscription in
                        NavigationLink { SubscriptionDetailView(subscription: subscription, repository: repository) } label: {
                            row(icon: "rectangle.stack.fill", title: subscription.name, subtitle: "\(subscription.organizerName) · \(subscription.season)")
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(suggestions) { suggestion in
                        NavigationLink { SubscriptionDetailView(subscription: suggestion.subscription, repository: repository) } label: {
                            row(icon: "sparkles", title: "Gibt es als Abo: \(suggestion.subscription.name)",
                                subtitle: "\(suggestion.matched) von \(suggestion.total) Konzerten hast du dir gemerkt · \(suggestion.subscription.organizerName)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            async let ownTask = PlannerAPI.mySubscriptions()
            async let suggestionsTask = PlannerAPI.suggestions()
            mine = await ownTask
            suggestions = await suggestionsTask
        }
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.headline).foregroundStyle(KlangradarTheme.accent)
                .frame(width: 40, height: 40)
                .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
