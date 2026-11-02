import SwiftUI
import UIKit

// Dynamic Type für feste Größen (02.11.2026): Stellen mit bewusst eigener
// Größe (große Zahlen, Symbole, Hero-Titel) wachsen jetzt mit der in iOS
// eingestellten Textgröße mit. Bei Standardgröße ist das Ergebnis identisch
// mit `.system(size:)` – Schriftart und Gewicht bleiben unverändert.
extension Font {
    static func scaled(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo style: UIFont.TextStyle = .body
    ) -> Font {
        let scaledSize = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        // Riesige Zahlen nicht unbegrenzt wachsen lassen (Layout bleibt lesbar).
        return .system(size: min(scaledSize, max(size * 1.6, size + 12)), weight: weight, design: design)
    }
}
