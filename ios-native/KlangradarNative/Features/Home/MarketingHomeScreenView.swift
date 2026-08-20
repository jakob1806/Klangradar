import SwiftUI

/// Homescreen-Nachbau für Social-Media-Screenshots: identisches Layout,
/// dieselben Komponenten (`EventCard`, `EventArtwork`, `KlangradarTheme`,
/// `KlangradarBackground`) wie `HomeView`, aber mit fest hinterlegten
/// Demo-Konzerten statt Supabase-Daten — kein Netzwerkzugriff, kein
/// ViewModel. Nur zum Erzeugen von Marketing-Screenshots verwenden, niemals
/// im echten Nutzerfluss einhängen.
struct MarketingHomeScreenView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var favorites = FavoriteStore(auth: AuthStore(service: nil), repository: nil)

    var body: some View {
        NavigationStack {
            ZStack {
                KlangradarBackground()
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        MarketingHeroEventView(
                            event: MarketingDemoData.hero,
                            height: horizontalSizeClass == .regular ? 280 : 224
                        )

                        ForEach(MarketingDemoData.rails) { rail in
                            MarketingEventRail(title: rail.title, events: rail.events)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
                .frame(maxWidth: KlangradarTheme.contentMaxWidth)
            }
            .navigationTitle("Klangradar")
        }
        .environmentObject(favorites)
    }
}

// MARK: - Demo-Daten

/// Hier frei anpassen: Titel, Untertitel, Datum/Uhrzeit, Ort und Bild-URL
/// je Konzert. `startDatetime` ist ISO 8601 in der Europe/Berlin-Zeitzone
/// (`"yyyy-MM-dd'T'HH:mm:ssZ"`); `imageUrls` nimmt eine oder mehrere
/// öffentlich erreichbare Bild-URLs, das erste Element wird verwendet.
private enum MarketingDemoData {
    struct Rail: Identifiable {
        let id = UUID()
        let title: String
        let events: [ConcertEvent]
    }

    static let hero = ConcertEvent(
        id: UUID(),
        slug: "sommerliches-orgelkonzert-muenchner-dom",
        title: "Sommerliches Orgelkonzert im Münchner Dom",
        subtitle: nil,
        startDatetime: "2026-08-21T19:30:00+02:00",
        imageUrls: ["https://images.unsplash.com/photo-1520523839897-bd0b52f945a0?w=1600&q=80"],
        status: "published",
        venues: VenueSummary(id: UUID(), name: "Frauenkirche (Dom zu Unserer Lieben Frau)")
    )

    static let rails: [Rail] = [
        Rail(title: "Für dich", events: [
            ConcertEvent(
                id: UUID(),
                slug: "bro-beethoven-9",
                title: "Symphonieorchester des Bayerischen Rundfunks: Beethoven 9",
                subtitle: nil,
                startDatetime: "2026-10-01T20:00:00+02:00",
                imageUrls: ["https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=1200&q=80"],
                status: "published",
                venues: VenueSummary(id: UUID(), name: "Isarphilharmonie")
            ),
            ConcertEvent(
                id: UUID(),
                slug: "simon-rattle-beethoven-9",
                title: "Sir Simon Rattle | Beethoven 9",
                subtitle: nil,
                startDatetime: "2026-09-24T19:00:00+02:00",
                imageUrls: ["https://images.unsplash.com/photo-1514320291840-2e0a9bf2a9ae?w=1200&q=80"],
                status: "published",
                venues: VenueSummary(id: UUID(), name: "Herkulessaal")
            ),
            ConcertEvent(
                id: UUID(),
                slug: "mozart-requiem",
                title: "Mozart Requiem",
                subtitle: nil,
                startDatetime: "2026-09-27T20:00:00+02:00",
                imageUrls: ["https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=1200&q=80"],
                status: "published",
                venues: VenueSummary(id: UUID(), name: "Prinzregententheater")
            )
        ]),
        Rail(title: "Münchner Philharmoniker", events: [
            ConcertEvent(
                id: UUID(),
                slug: "philharmoniker-strawinsky-ravel",
                title: "Münchner Philharmoniker: Strawinsky & Ravel",
                subtitle: nil,
                startDatetime: "2026-10-02T20:00:00+02:00",
                imageUrls: ["https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=1200&q=80"],
                status: "published",
                venues: VenueSummary(id: UUID(), name: "Isarphilharmonie")
            ),
            ConcertEvent(
                id: UUID(),
                slug: "philharmoniker-bruckner-8",
                title: "Münchner Philharmoniker: Bruckner 8",
                subtitle: nil,
                startDatetime: "2026-10-03T19:30:00+02:00",
                imageUrls: ["https://images.unsplash.com/photo-1465847899084-d164df4dedc6?w=1200&q=80"],
                status: "published",
                venues: VenueSummary(id: UUID(), name: "Isarphilharmonie")
            )
        ])
    ]
}

// MARK: - Layout (1:1 Kopie der Darstellung aus HomeView)

/// Exakter Nachbau von `HeroEventView` aus `HomeView.swift` — dieselbe
/// Schrift, Abstände, Verlauf und Kartenform, nur ohne `NavigationLink`.
private struct MarketingHeroEventView: View {
    let event: ConcertEvent
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            EventArtwork(event: event)
                .frame(width: proxy.size.width, height: height)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.16), location: 0.28),
                            .init(color: .black.opacity(0.86), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: min(height * 0.72, 170))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(heroDate(event))
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.9))

                        Text(event.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(event.subtitle ?? event.venueName, systemImage: "mappin")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.34), radius: 7, y: 2)
                    .padding(18)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .clipShape(.rect(cornerRadius: 24))
        }
        .frame(height: height)
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .accessibilityElement(children: .combine)
    }

    private func heroDate(_ event: ConcertEvent) -> String {
        guard let date = event.startDate else { return "NÄCHSTE VERANSTALTUNG" }
        let day = KlangradarDateTime.calendar.isDateInToday(date) ? "HEUTE" : KlangradarDateTime.string(date, format: "EEE, d. MMM").uppercased()
        return "\(day) · \(date.formatted(date: .omitted, time: .shortened))"
    }
}

/// Exakter Nachbau von `EventRail` aus `HomeView.swift` — nutzt dieselbe
/// `EventCard`, denselben Titel-Font und dieselben Abstände.
private struct MarketingEventRail: View {
    let title: String
    let events: [ConcertEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, KlangradarTheme.pagePadding)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(events) { event in
                            EventCard(event: event)
                        }
                    }
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

#Preview {
    MarketingHomeScreenView()
}
