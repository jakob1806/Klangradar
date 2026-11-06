// Erstellt von Claude Code (Nutzerwunsch 24.10.2026, Punkte 1+2).
import ActivityKit
import Foundation
import UserNotifications

/// Bringt die vom Abendfahrplan (EveningPlanSection) berechnete Losgeh-Zeit
/// in Live Activity und eine Erinnerung. Die Erinnerung kommt nicht zu einer
/// festen Uhrzeit, sondern 5 Min. bevor man vom aktuellen Standort aus
/// losmuss; jede neue Berechnung (Standortwechsel, Verkehr) verschiebt sie.
@MainActor
final class ConcertDayCoordinator {
    static let shared = ConcertDayCoordinator()

    struct Plan: Equatable {
        let slug: String
        let title: String
        let venue: String
        let start: Date
        let leaveAt: Date
        let travel: String
        let pauseAt: Date?
        var times: ConcertTimes? = nil
    }

    private var lastPlans: [String: Plan] = [:]

    /// Nur für gemerkte Konzerte innerhalb der nächsten 24 h.
    func update(_ plan: Plan) async {
        guard lastPlans[plan.slug] != plan else { return }
        let isSaved = SharedConcertStore.load().contains { $0.slug == plan.slug }
        let untilStart = plan.start.timeIntervalSinceNow
        guard isSaved, untilStart > -3600, untilStart < 24 * 3600 else { return }
        lastPlans[plan.slug] = plan
        await updateActivity(plan)
        await scheduleReminder(plan)
    }

    private func updateActivity(_ plan: Plan) async {
        for activity in Activity<ConcertActivityAttributes>.activities where activity.attributes.slug == plan.slug {
            var state = activity.content.state
            state.leaveAt = plan.leaveAt
            state.travel = plan.travel
            if let times = plan.times { state.apply(times) } else if let pause = plan.pauseAt { state.pauseAt = pause }
            await activity.update(ActivityContent(state: state, staleDate: plan.start.addingTimeInterval(3 * 3600)))
        }
    }

    private func scheduleReminder(_ plan: Plan) async {
        let center = UNUserNotificationCenter.current()
        let id = "leave-\(plan.slug)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let fireAt = plan.leaveAt.addingTimeInterval(-5 * 60)
        guard fireAt > Date().addingTimeInterval(30) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "In 5 Minuten losgehen"
        content.body = "\(plan.travel) zu „\(plan.title)“ · \(plan.venue)"
        content.sound = .default
        content.threadIdentifier = "concert-day"
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["route": "/event/\(plan.slug)", "event_slug": plan.slug, "kind": "leave_reminder"]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await center.add(request)
    }
}


struct ConcertTimes: Equatable {
    var doorsAt: Date?
    var doorsEstimated = true
    var pauseAt: Date?
    var pauseEndAt: Date?
    var endAt: Date?
    var endEstimated = true

    /// `detail` ist eine Event-Zeile mit `end_datetime`, `duration_minutes`,
    /// `has_intermission` und optional `venues.doors_info_de`.
    static func compute(start: Date, detail: JSONObject) -> ConcertTimes {
        var times = ConcertTimes()

        // Ende: echtes Ende, sonst Beginn + Dauer.
        if let raw = detail.string("end_datetime"), let end = FlexibleDateParser.date(from: raw), end > start {
            times.endAt = end; times.endEstimated = false
        } else if let minutes = detail.integer("duration_minutes"), minutes > 0 {
            times.endAt = start.addingTimeInterval(TimeInterval(minutes * 60)); times.endEstimated = false
        }

        // Pause: nur wenn das Konzert eine hat; Mitte des Abends, 20 Min.
        if detail.bool("has_intermission") == true {
            let length = times.endAt.map { $0.timeIntervalSince(start) } ?? 120 * 60
            let pause = start.addingTimeInterval(length / 2 - 10 * 60)
            times.pauseAt = pause
            times.pauseEndAt = pause.addingTimeInterval(20 * 60)
        }

        // Einlass: aus dem Text der Spielstätte („Einlass 60 Minuten vor
        // Beginn“, „eine Stunde vorher“), sonst ca. 45 Min. vorher.
        let info = detail.object("venues")?.string("doors_info_de") ?? detail.string("doors_info_de")
        if let minutes = info.flatMap(doorsMinutes(in:)) {
            times.doorsAt = start.addingTimeInterval(TimeInterval(-minutes * 60)); times.doorsEstimated = false
        } else {
            times.doorsAt = start.addingTimeInterval(-45 * 60)
        }
        return times
    }

    static func doorsMinutes(in text: String) -> Int? {
        let lower = text.lowercased()
        guard lower.contains("einlass") || lower.contains("öffn") || lower.contains("vor beginn") || lower.contains("vorher") else { return nil }
        if lower.contains("eine stunde") || lower.contains("1 stunde") { return 60 }
        if lower.contains("eine halbe stunde") || lower.contains("halbe stunde") { return 30 }
        if let match = lower.range(of: #"(\d{2,3})\s*(minuten|min\.?)"#, options: .regularExpression) {
            let digits = lower[match].prefix { $0.isNumber }
            if let value = Int(digits), (10...120).contains(value) { return value }
        }
        return nil
    }
}
