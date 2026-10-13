import ActivityKit
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import WidgetKit

/// Hält Widget, Spotlight-Suche und Live Activity mit den gemerkten,
/// kommenden Konzerten synchron. Läuft beim App-Start, beim Zurückkehren in
/// die App und nach jeder Änderung der Favoriten.
@MainActor
final class ConcertSync {
    static let shared = ConcertSync()
    static let spotlightDomain = "favorite-events"

    func refresh(favoriteIDs: Set<UUID>, repository: any EventRepository) async {
        let events = favoriteIDs.isEmpty ? [] : ((try? await repository.events(ids: Array(favoriteIDs))) ?? [])
        let concerts = events.compactMap { event -> SharedConcert? in
            guard let start = event.startDate else { return nil }
            return SharedConcert(id: event.id.uuidString.lowercased(), slug: event.slug, title: event.title, venue: event.venueName, start: start)
        }.sorted { $0.start < $1.start }

        SharedConcertStore.save(Array(concerts.prefix(10)))
        WidgetCenter.shared.reloadAllTimelines()
        indexSpotlight(concerts)
        await updateLiveActivities(concerts)
    }

    private func indexSpotlight(_ concerts: [SharedConcert]) {
        let items = concerts.map { concert -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = concert.title
            attributes.contentDescription = "\(concert.start.formatted(date: .abbreviated, time: .shortened)) · \(concert.venue)"
            attributes.keywords = ["Konzert", "Klangradar", concert.venue]
            let item = CSSearchableItem(uniqueIdentifier: "event:\(concert.slug)", domainIdentifier: Self.spotlightDomain, attributeSet: attributes)
            item.expirationDate = concert.start.addingTimeInterval(6 * 3600)
            return item
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [Self.spotlightDomain]) { _ in
            if !items.isEmpty { index.indexSearchableItems(items) }
        }
    }

    /// Am Konzerttag (ab 4 h vor Beginn) eine Live Activity starten; nach
    /// dem Konzert (Beginn + 3 h) wieder beenden.
    private func updateLiveActivities(_ concerts: [SharedConcert]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date.now
        for activity in Activity<ConcertActivityAttributes>.activities {
            let ended = activity.attributes.start.addingTimeInterval(3 * 3600) < now
            let unfavorited = !concerts.contains { $0.slug == activity.attributes.slug }
            if ended || unfavorited { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let running = Set(Activity<ConcertActivityAttributes>.activities.map(\.attributes.slug))
        for concert in concerts where !running.contains(concert.slug) {
            let untilStart = concert.start.timeIntervalSince(now)
            guard untilStart <= 4 * 3600, untilStart > -3600 else { continue }
            let attributes = ConcertActivityAttributes(slug: concert.slug, title: concert.title, venue: concert.venue, start: concert.start)
            let content = ActivityContent(state: ConcertActivityAttributes.ContentState(phase: "upcoming"), staleDate: concert.start.addingTimeInterval(3 * 3600))
            _ = try? Activity.request(attributes: attributes, content: content)
        }
    }
}
