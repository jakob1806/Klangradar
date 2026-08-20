import SwiftUI

/// Kleine UI-Bausteine, die von mehreren Redaktions-Bildschirmen genutzt
/// werden (Dashboard, Event-/Entity-Editor) — daher hier statt in einer der
/// einzelnen Editor-Dateien, um zirkuläre "wer gehört wem"-Abhängigkeiten zu
/// vermeiden.

struct EditorialModeBanner: View {
    var compact = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("REDAKTIONSMODUS").font(.caption.bold()).tracking(1.3).foregroundStyle(.orange)
                    Text("LIVE").font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.orange.opacity(0.16), in: Capsule()).foregroundStyle(.orange)
                }
                if !compact { Text("Änderungen werden sofort plattformweit veröffentlicht.").font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.35)) }
    }
}

struct EditorialBackground: View {
    var body: some View { KlangradarBackground().ignoresSafeArea() }
}

struct EditorialCard<Content: View>: View {
    let title: String; let icon: String; @ViewBuilder let content: Content
    init(title: String, icon: String, @ViewBuilder content: () -> Content) { self.title = title; self.icon = icon; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(KlangradarTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(KlangradarTheme.accent)
                Text(title).font(.headline).foregroundStyle(.primary)
            }
            content
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.separator.opacity(0.18)) }
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

struct EditorialPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(13)
            .background(KlangradarTheme.accent.opacity(configuration.isPressed ? 0.72 : 1), in: .rect(cornerRadius: 12))
            .foregroundStyle(.white)
    }
}

/// Einfache Suchliste zur Auswahl EINER Option (Komponist:in, Ensemble,
/// Venue, …) — genutzt von CreateFlows, EntityEditor und EventEditor.
struct EditorialSimpleOptionPicker: View {
    let title: String
    let options: [EditorialOption]
    let onSelect: (EditorialOption) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [EditorialOption] { search.isEmpty ? options : options.filter { $0.title.localizedStandardContains(search) } }
    var body: some View {
        NavigationStack {
            List(filtered) { option in Button(option.title) { onSelect(option); dismiss() }.foregroundStyle(.primary) }
                .searchable(text: $search)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}
