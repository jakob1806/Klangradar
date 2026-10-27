// Erstellt von Claude Code (Nutzerwunsch 27.10.2026): eine Quelle für alle
// Plus-Funktionen – Paywall, Willkommen, Plus-Übersicht und die Hinweise an
// den einzelnen Stellen der App erzählen dasselbe, inklusive "wo finde ich das".
import SwiftUI
import UIKit
import UserNotifications

enum PlusFeature: String, CaseIterable, Identifiable {
    case instantAlerts, coach, concertYear, lists, appIcons, partners

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instantAlerts: "Neue Termine sofort"
        case .coach: "Klangradar KI ohne Limit"
        case .concertYear: "Dein Konzertjahr komplett"
        case .lists: "Unbegrenzte Listen"
        case .appIcons: "Eigene App-Icons"
        case .partners: "Partner-Vorteile"
        }
    }

    /// Ein Satz: was man davon hat.
    var pitch: String {
        switch self {
        case .instantAlerts: "Kündigt jemand, dem du folgst, ein Konzert an, erfährst du es noch am selben Tag. Ohne Plus kommt das einmal täglich gesammelt."
        case .coach: "Programme erklären, Abende planen, Werke vorbereiten. Ohne Plus sind es \(CoachQuota.weeklyLimit) Fragen pro Woche."
        case .concertYear: "Monatsrhythmus, Lieblingstag, deine Säle und Mitwirkenden, dazu ein Bild im Story-Format."
        case .lists: "Ohne Plus sind es \(PlusLimits.freeLists). Mit Plus sammelst du für jede Saison und jeden Anlass."
        case .appIcons: "Nacht, Gold, Indigo oder Mono: Klangradar so auf dem Homescreen, wie es dir gefällt."
        case .partners: "Gutscheincodes von Konzerthäusern und Partnern, sobald welche verfügbar sind."
        }
    }

    /// Wo die Funktion in der App sitzt.
    var whereToFind: String {
        switch self {
        case .instantAlerts: "Läuft automatisch, sobald du Künstler:innen, Ensembles oder Orten folgst."
        case .coach: "Profil → Klangradar KI, und bei jedem Werk unter „Einführung“."
        case .concertYear: "Profil → Dein Konzertjahr."
        case .lists: "Profil → Mein Klangradar → Meine Listen."
        case .appIcons: "Profil → Klangradar Plus → App-Icon."
        case .partners: "Profil → Partner-Vorteile."
        }
    }

    var symbol: String {
        switch self {
        case .instantAlerts: "bell.badge.fill"
        case .coach: "sparkles"
        case .concertYear: "chart.bar.fill"
        case .lists: "list.bullet.rectangle.fill"
        case .appIcons: "app.badge.fill"
        case .partners: "gift.fill"
        }
    }

    var color: Color {
        switch self {
        case .instantAlerts: .orange
        case .coach: .purple
        case .concertYear: .indigo
        case .lists: .teal
        case .appIcons: .pink
        case .partners: .red
        }
    }

    /// Text oben in der Paywall, wenn sie von dieser Funktion aus geöffnet wird.
    var paywallReason: String {
        switch self {
        case .instantAlerts: "Mit Plus erfährst du sofort von neuen Konzerten deiner Künstler:innen."
        case .coach: "Du hast diese Woche deine \(CoachQuota.weeklyLimit) kostenlosen Fragen an die Klangradar KI genutzt."
        case .concertYear: "Dein ganzes Konzertjahr gibt es mit Plus."
        case .lists: "Ohne Plus kannst du \(PlusLimits.freeLists) Listen anlegen."
        case .appIcons: "Eigene App-Icons gibt es mit Plus."
        case .partners: "Die Gutscheincodes unserer Partner gibt es mit Plus."
        }
    }
}

/// Kleines "PLUS"-Etikett an Funktionen, die Plus brauchen oder erweitern.
struct PlusBadge: View {
    var body: some View {
        Text("PLUS")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(PlusStyle.gradient, in: .capsule)
            .accessibilityLabel("Klangradar Plus")
    }
}

enum PlusStyle {
    static var gradient: LinearGradient {
        LinearGradient(colors: [KlangradarTheme.accent, .indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Alternative App-Icons (Plus). Namen entsprechen den Icon-Sets in
/// Assets.xcassets und ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard, nacht = "AppIcon-Nacht", gold = "AppIcon-Gold", indigo = "AppIcon-Indigo", mono = "AppIcon-Mono"

    var id: String { rawValue }
    var iconName: String? { self == .standard ? nil : rawValue }
    var previewImage: String { self == .standard ? "AppIcon-Standard-Preview" : "\(rawValue)-Preview" }
    var label: String {
        switch self {
        case .standard: "Standard"
        case .nacht: "Nacht"
        case .gold: "Gold"
        case .indigo: "Indigo"
        case .mono: "Mono"
        }
    }

    @MainActor static var current: AppIconChoice {
        AppIconChoice(rawValue: UIApplication.shared.alternateIconName ?? "") ?? .standard
    }

    @MainActor func apply() async {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        try? await UIApplication.shared.setAlternateIconName(iconName)
    }
}

/// Erinnert zwei Tage vor Ende der kostenlosen Testphase – damit niemand
/// von der ersten Abbuchung überrascht wird.
enum PlusTrialReminder {
    static func schedule(trialDays: Int, price: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Deine Plus-Testphase endet in 2 Tagen"
        content.body = "Danach kostet Plus \(price). Kündigen kannst du jederzeit in den Einstellungen deines Apple-Accounts."
        content.sound = .default
        let seconds = TimeInterval(max(1, trialDays - 2)) * 86_400
        let request = UNNotificationRequest(identifier: "plus-trial-reminder", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        center.removePendingNotificationRequests(withIdentifiers: ["plus-trial-reminder"])
        center.add(request)
    }
}
