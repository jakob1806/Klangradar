import SwiftUI
import TipKit

// Tipps beim ersten Benutzen (TipKit, 02.11.2026). Jeder Tipp erscheint
// höchstens einmal; TipKit merkt sich das selbst.

struct FollowBellTip: Tip {
    var title: Text { Text("Folgen ohne Mitteilungen") }
    var message: Text? { Text("Mit der Glocke legst du fest, ob du bei neuen Konzerten benachrichtigt wirst – folgen kannst du trotzdem.") }
    var image: Image? { Image(systemName: "bell.badge") }
}

struct ConcertLongPressTip: Tip {
    var title: Text { Text("Lange drücken") }
    var message: Text? { Text("Halte ein Konzert gedrückt, um es zu merken oder zu teilen, ohne es zu öffnen.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

struct WrongImageTip: Tip {
    var title: Text { Text("Falsches Foto?") }
    var message: Text? { Text("Zeigt ein Bild die falsche Person, tippe auf „Falsches Bild?“ – wir kümmern uns darum.") }
    var image: Image? { Image(systemName: "photo.badge.exclamationmark") }
}

enum KlangradarTips {
    static func configure() {
        // UI-Tests ohne Tipps, sonst überdecken Popover die Bedienelemente.
        if ProcessInfo.processInfo.environment["KLANGRADAR_UI_TEST"] == "1" {
            Tips.hideAllTipsForTesting()
        }
        try? Tips.configure([.displayFrequency(.daily)])
    }
}
