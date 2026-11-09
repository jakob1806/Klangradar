import SwiftUI

/// Rechtstext aus LegalTexts (Quelle: docs/legal/legal_texts.py, 09.11.2026).
struct ImpressumView: View {
    var body: some View {
        LegalTextList(sections: LegalTexts.impressum)
            .navigationTitle("Impressum")
            .navigationBarTitleDisplayMode(.inline)
    }
}
