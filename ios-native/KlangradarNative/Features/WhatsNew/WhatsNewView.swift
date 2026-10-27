// Erstellt von Claude Code (Nutzerwunsch 27.10.2026): "Neu in Klangradar"
// einmal nach jedem Update. Inhalt aus Resources/WhatsNew.json – dieselbe
// Datei liefert den TestFlight-Testhinweis (Scripts/testflight_whats_new.rb).
import SwiftUI

struct WhatsNewNotes: Decodable {
    struct Section: Decodable, Identifiable {
        let title: String
        let symbol: String
        let items: [String]
        var id: String { title }
    }
    let id: String
    let title: String
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
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notes.title).font(.largeTitle.bold())
                        Text(version).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    ForEach(notes.sections) { section in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: section.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(KlangradarTheme.accent.gradient, in: .rect(cornerRadius: 13, style: .continuous))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title).font(.headline)
                                ForEach(section.items, id: \.self) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("•").foregroundStyle(KlangradarTheme.accent)
                                        Text(item).font(.subheadline).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(KlangradarTheme.pagePadding)
                .padding(.bottom, 90)
            }
            .safeAreaInset(edge: .bottom) {
                if isModal {
                Button { dismiss() } label: {
                    Text("Weiter").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(KlangradarTheme.accent)
                .padding(.horizontal, KlangradarTheme.pagePadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
                }
            }
            .background { KlangradarBackground().ignoresSafeArea() }
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
