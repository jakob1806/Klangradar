import ActivityKit
import CoreSpotlight
import Foundation
import UIKit
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
        await cacheActivityImages(for: events)
        WidgetCenter.shared.reloadAllTimelines()
        indexSpotlight(concerts)
        await updateLiveActivities(concerts)
    }

    /// Bilder der Konzerte in den nächsten 24 h verkleinert für die
    /// Live-Aktivität ablegen (höchstens ein Download je Konzert).
    private func cacheActivityImages(for events: [ConcertEvent]) async {
        let soon = events.filter { ($0.startDate ?? .distantPast).timeIntervalSinceNow < 24 * 3600 && ($0.startDate ?? .distantPast) > .now.addingTimeInterval(-3 * 3600) }
        for event in soon {
            guard let target = SharedActivityImageStore.url(forSlug: event.slug),
                  !FileManager.default.fileExists(atPath: target.path),
                  let source = event.primaryImageURL,
                  let (data, _) = try? await URLSession.shared.data(from: source),
                  let image = UIImage(data: data) else { continue }
            let width: CGFloat = 400
            let size = CGSize(width: width, height: width * image.size.height / max(image.size.width, 1))
            let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            try? small.jpegData(compressionQuality: 0.7)?.write(to: target)
        }
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
