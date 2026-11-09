import SwiftUI

/// Gemeinsame Darstellung der Rechtstexte (09.11.2026).
struct LegalTextList: View {
    let sections: [(title: String, body: String)]

    var body: some View {
        List {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    Text(section.body).font(.subheadline).textSelection(.enabled)
                }
            }
            Section {
                Text("Stand: \(LegalTexts.stand)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
