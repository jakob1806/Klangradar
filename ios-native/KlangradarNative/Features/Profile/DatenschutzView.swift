import SwiftUI

/// Rechtstext aus LegalTexts (Quelle: docs/legal/legal_texts.py, 09.11.2026).
struct DatenschutzView: View {
    var body: some View {
        LegalTextList(sections: LegalTexts.datenschutz)
            .navigationTitle("Datenschutz")
            .navigationBarTitleDisplayMode(.inline)
    }
}
