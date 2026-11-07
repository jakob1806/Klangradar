import ActivityKit
@preconcurrency import CoreSpotlight
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

    private var observedTokens: Set<String> = []

    /// Token der Live-Aktivität in live_activity_tokens hinterlegen.
    private func observePushToken(_ activity: Activity<ConcertActivityAttributes>, eventID: String) {
        guard observedTokens.insert(activity.id).inserted else { return }
        Task {
            for await data in activity.pushTokenUpdates {
                #if DEBUG
                let environment = "dev"
                #else
                let environment = "prod"
                #endif
                let token = "apns:\(environment):" + data.map { String(format: "%02x", $0) }.joined()
                guard let client = SocialStore.shared.repository?.client, let access = SocialStore.shared.token,
                      let userID = SocialStore.shared.auth?.userID else { continue }
                try? await client.upsert(table: "live_activity_tokens", values: [
                    "token": .string(token),
                    "user_id": .string(userID.uuidString),
                    "event_id": .string(eventID)
                ], accessToken: access, conflictColumns: "token")
            }
        }
    }

    /// Programm mit Werkdauern (nur wenn alle Werke eine Dauer haben, sonst
    /// wäre „Jetzt läuft“ geraten). Höchstens 8 Werke, Titel gekürzt.
    static func loadProgram(eventID: String) async -> [(String, Int)]? {
        guard let client = SocialStore.shared.repository?.client else { return nil }
        let rows: [JSONObject]? = try? await client.get(table: "event_works", queryItems: [
            URLQueryItem(name: "select", value: "position,works(title,duration_minutes,composer:persons!works_composer_id_fkey(full_name))"),
            URLQueryItem(name: "event_id", value: "eq.\(eventID)"),
            URLQueryItem(name: "order", value: "position.asc")
        ])
        guard let rows, !rows.isEmpty, rows.count <= 8 else { return nil }
        var items: [(String, Int)] = []
        for row in rows {
            guard let work = row.object("works"), let minutes = work.integer("duration_minutes"), minutes > 0 else { return nil }
            let composer = work.object("composer")?.string("full_name")?.split(separator: " ").last.map(String.init)
            let title = String((work.string("title") ?? "Werk").prefix(40))
            items.append(([composer, title].compactMap { $0 }.joined(separator: ": "), minutes))
        }
        return items
    }

    /// Einlass/Pause/Ende für die Live-Aktivität aus der Event-Zeile.
    static func loadTimes(eventID: String, start: Date) async -> ConcertTimes? {
        guard let client = SocialStore.shared.repository?.client else { return nil }
        let rows: [JSONObject]? = try? await client.get(table: "events", queryItems: [
            URLQueryItem(name: "select", value: "end_datetime,duration_minutes,has_intermission,venues(doors_info_de)"),
            URLQueryItem(name: "id", value: "eq.\(eventID)")
        ])
        return rows?.first.map { ConcertTimes.compute(start: start, detail: $0) }
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
        for activity in Activity<ConcertActivityAttributes>.activities {
            if let concert = concerts.first(where: { $0.slug == activity.attributes.slug }) { observePushToken(activity, eventID: concert.id) }
        }
        let running = Set(Activity<ConcertActivityAttributes>.activities.map(\.attributes.slug))
        for concert in concerts where !running.contains(concert.slug) {
            let untilStart = concert.start.timeIntervalSince(now)
            guard untilStart <= 4 * 3600, untilStart > -3600 else { continue }
            let attributes = ConcertActivityAttributes(slug: concert.slug, title: concert.title, venue: concert.venue, start: concert.start)
            var state = ConcertActivityAttributes.ContentState(phase: "upcoming")
            if let times = await Self.loadTimes(eventID: concert.id, start: concert.start) { state.apply(times) }
            if let program = await Self.loadProgram(eventID: concert.id) {
                state.programTitles = program.map(\.0)
                state.programMinutes = program.map(\.1)
            }
            let content = ActivityContent(state: state, staleDate: (state.endAt ?? concert.start.addingTimeInterval(3 * 3600)).addingTimeInterval(1800))
            // Mit Push-Token (06.11.2026): Server-Updates bei Absage,
            // Zeit- oder Besetzungsänderung.
            if let activity = try? Activity.request(attributes: attributes, content: content, pushType: .token) {
                observePushToken(activity, eventID: concert.id)
            }
        }
    }
}

extension ConcertActivityAttributes.ContentState {
    mutating func apply(_ times: ConcertTimes) {
        doorsAt = times.doorsAt; doorsEstimated = times.doorsEstimated
        pauseAt = times.pauseAt; pauseEndAt = times.pauseEndAt
        endAt = times.endAt; endEstimated = times.endEstimated
    }
}
