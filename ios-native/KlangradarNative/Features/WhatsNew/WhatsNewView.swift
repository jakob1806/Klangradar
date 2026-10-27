// Erstellt von Claude Code (Nutzerwunsch 27.10.2026): "Neu in Klangradar"
// einmal nach jedem Update. Inhalt aus Resources/WhatsNew.json – dieselbe
// Datei liefert den TestFlight-Testhinweis (Scripts/testflight_whats_new.rb).
import SwiftUI

struct WhatsNewNotes: Decodable {
    struct Section: Decodable, Identifiable {
        let title: String
        /// Wird seit dem schlichteren Layout (27.10.2026) nicht mehr angezeigt.
        let symbol: String?
        let items: [String]
        var id: String { title }
    }
    let id: String
    let title: String
    /// Ein, zwei Sätze vorweg (optional).
    let intro: String?
    let sections: [Section]

    static let current: WhatsNewNotes? = {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WhatsNewNotes.self, from: data)
    }()
}

struct WhatsNewView: View {
    let notes: WhatsNewNotes
    /// false, wenn aus dem Profil aufgerufen (dort per Navigation, ohne "Weiter").
    var isModal = false
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "Version \(short) (\(build))"
    }

    var body: some View {
        if isModal {
            NavigationStack { content }.presentationDragIndicator(.visible)
        } else {
            content.navigationTitle("Neu in dieser Version").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(version.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                Text(notes.title)
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .padding(.top, 6)
                if let intro = notes.intro {
                    Text(intro)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                ForEach(notes.sections) { section in
                    Divider().padding(.vertical, 22)
                    Text(section.title)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.items, id: \.self) { item in
                            Text(item)
                                .font(.body)
                                .foregroundStyle(.primary.opacity(0.8))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, KlangradarTheme.pagePadding + 4)
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            if isModal {
                Button { dismiss() } label: {
                    Text("Weiter").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(KlangradarTheme.accent)
                .frame(maxWidth: 520)
                .padding(.horizontal, KlangradarTheme.pagePadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

/// Zeigt "Neu in Klangradar" einmal je Notiz-ID – nicht bei Erstinstallation
/// (dort läuft das Onboarding), nicht in UI-Tests/Marketing-Aufnahmen.
private struct WhatsNewGate: ViewModifier {
    let isBlocked: Bool
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @AppStorage("whatsNewSeenID") private var seenID = ""
    @State private var notes: WhatsNewNotes?

    func body(content: Content) -> some View {
        content
            .task(id: isBlocked) {
                let env = ProcessInfo.processInfo.environment
                guard env["KLANGRADAR_UI_TEST"] != "1", env["KLANGRADAR_MARKETING_CAPTURE"] != "1",
                      let current = WhatsNewNotes.current, current.id != seenID else { return }
                guard didCompleteOnboarding else { seenID = current.id; return }
                guard !isBlocked else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                notes = current
            }
            .sheet(item: Binding(get: { notes.map(Shown.init) }, set: { if $0 == nil, let notes { seenID = notes.id; self.notes = nil } })) { shown in
                WhatsNewView(notes: shown.notes, isModal: true)
            }
    }

    private struct Shown: Identifiable {
        let notes: WhatsNewNotes
        var id: String { notes.id }
    }
}

extension View {
    func whatsNewSheet(blocked: Bool) -> some View { modifier(WhatsNewGate(isBlocked: blocked)) }
}
