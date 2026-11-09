import SwiftUI

/// Rechtstext aus LegalTexts (Quelle: docs/legal/legal_texts.py, 09.11.2026).
struct AGBView: View {
    var body: some View {
        LegalTextList(sections: LegalTexts.agb)
            .navigationTitle("Nutzungsbedingungen")
            .navigationBarTitleDisplayMode(.inline)
    }
}
