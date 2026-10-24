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
            state.pauseAt = plan.pauseAt
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
