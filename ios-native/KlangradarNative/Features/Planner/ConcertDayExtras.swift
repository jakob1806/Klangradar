// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Ergänzungen der
// Konzertseite – Kurzporträts von Dirigent:in/Solist:innen für "In 3 Minuten
// vorbereitet", Hinweis auf Besetzungsänderungen und eigener Sitzplatz.
import SwiftUI

/// Wer steht auf der Bühne? Zwei Sätze aus der Biografie plus aktuelle Position.
struct PerformerBriefs: View {
    let detail: JSONObject

    struct Brief: Identifiable {
        let id: UUID
        let name: String
        let role: String?
        let photoURL: URL?
        let route: EntityRoute?
        let text: String
        let fullText: String
    }

    @State private var briefs: [Brief] = []
    @State private var expanded: Set<UUID> = []

    /// Nutzerwunsch 26.10.2026: Kurzporträts nur bei bis zu 4 Künstler:innen –
    /// bei größeren Besetzungen bleibt es bei der Mitwirkenden-Liste.
    private var candidates: [(id: UUID, role: String?)] {
        var seen = Set<UUID>()
        let all = detail.objects("event_participants").compactMap { row -> (id: UUID, role: String?)? in
            guard let person = row.object("persons"), let id = person.string("id").flatMap(UUID.init(uuidString:)), seen.insert(id).inserted else { return nil }
            return (id, row.string("role_label") ?? row.string("role"))
        }
        return all.count <= 4 ? all : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !briefs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wer spielt?").font(.headline)
                    ForEach(briefs) { brief in
                        VStack(alignment: .leading, spacing: 8) {
                            profileLink(brief) {
                            HStack(spacing: 10) {
                                CachedAsyncImage(url: brief.photoURL) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { Image(systemName: "person.fill").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.12)) }
                                }
                                .frame(width: 40, height: 40).clipShape(.circle)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(brief.name).font(.subheadline.weight(.semibold))
                                    if let role = brief.role { Text(role).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                if brief.route != nil {
                                    Text("Profil").font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(KlangradarTheme.accent)
                                }
                            }
                            }
                            Text(expanded.contains(brief.id) ? brief.fullText : brief.text)
                                .font(.footnote).foregroundStyle(.primary.opacity(0.85))
                            if brief.fullText.count > brief.text.count {
                                Button(expanded.contains(brief.id) ? "Weniger" : "Mehr lesen") {
                                    withAnimation(.snappy) {
                                        if expanded.contains(brief.id) { expanded.remove(brief.id) } else { expanded.insert(brief.id) }
                                    }
                                }
                                .font(.caption.weight(.semibold)).tint(KlangradarTheme.accent)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .task(id: candidates.map(\.id)) { await load() }
    }

    @ViewBuilder private func profileLink<Content: View>(_ brief: Brief, @ViewBuilder content: () -> Content) -> some View {
        if let route = brief.route {
            NavigationLink(value: route) { content().contentShape(.rect) }.buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func load() async {
        let list = candidates
        guard !list.isEmpty, let client = SocialStore.shared.repository?.client else { return }
        let rows: [JSONObject]? = try? await client.get(table: "persons", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,full_name,photo_url,biography_de,current_roles_de,instrument"),
            URLQueryItem(name: "id", value: "in.(\(list.map(\.id.uuidString).joined(separator: ",")))")
        ])
        let byID = Dictionary((rows ?? []).compactMap { row in row.string("id").flatMap(UUID.init(uuidString:)).map { ($0, row) } }, uniquingKeysWith: { a, _ in a })
        briefs = list.compactMap { candidate in
            guard let row = byID[candidate.id], let name = row.string("full_name") else { return nil }
            let bio = (row.string("biography_de") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let current = row.string("current_roles_de")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let full = [current, bio].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n\n")
            guard !full.isEmpty else { return nil }
            return Brief(id: candidate.id, name: name, role: candidate.role ?? row.string("instrument"),
                         photoURL: row.string("photo_url").flatMap(URL.init(string:)),
                         route: EntityRoute(kind: .person, identifier: row.string("slug") ?? candidate.id.uuidString), text: Self.firstSentences(full, count: 2), fullText: full)
        }
    }

    static func firstSentences(_ text: String, count: Int) -> String {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, stop in
            if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if sentences.count >= count { stop = true }
        }
        return sentences.isEmpty ? text : sentences.joined(separator: " ")
    }
}

/// Neueste Besetzungsänderung aus event_changes (field_name = cast).
struct CastChangeBanner: View {
    let eventID: UUID
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.2.badge.gearshape.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Besetzungsänderung").font(.subheadline.weight(.semibold))
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
        .task(id: eventID) {
            guard let client = SocialStore.shared.repository?.client else { return }
            let rows: [JSONObject]? = try? await client.get(table: "event_changes", queryItems: [
                URLQueryItem(name: "select", value: "old_value,new_value,changed_at"),
                URLQueryItem(name: "event_id", value: "eq.\(eventID.uuidString)"),
                URLQueryItem(name: "field_name", value: "eq.cast"),
                URLQueryItem(name: "order", value: "changed_at.desc"),
                URLQueryItem(name: "limit", value: "1")
            ])
            guard let row = rows?.first else { return }
            let added = row.string("new_value"), removed = row.string("old_value")
            switch (added, removed) {
            case let (a?, r?): message = "\(a) statt \(r)"
            case let (a?, nil): message = "Neu dabei: \(a)"
            case let (nil, r?): message = "Nicht mehr dabei: \(r)"
            default: message = nil
            }
        }
    }
}

/// Eigener Platz (nur lokal) plus Saalplan der Spielstätte, falls gepflegt.
struct SeatCard: View {
    let event: ConcertEvent
    let detail: JSONObject
    @State private var seat = ConcertSeat()
    @State private var isEditing = false
    @State private var seatingPlanURL: URL?

    private var isUpcoming: Bool { (event.startDate ?? .distantPast).addingTimeInterval(3 * 3600) > .now }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUpcoming {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "chair.fill").font(.title3).foregroundStyle(KlangradarTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seat.isEmpty ? "Dein Platz" : seat.summary).font(.headline).lineLimit(2)
                            Text(seat.isEmpty ? "Eintragen – erscheint am Konzerttag auf dem Sperrbildschirm." : "Wird am Konzerttag in der Live-Aktivität angezeigt.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button(seat.isEmpty ? "Eintragen" : "Ändern") { isEditing = true }.font(.subheadline.weight(.semibold))
                    }
                    if let seatingPlanURL {
                        Link(destination: seatingPlanURL) {
                            Label("Saalplan ansehen", systemImage: "square.grid.3x3.topleft.filled").font(.subheadline.weight(.semibold))
                        }
                        .tint(KlangradarTheme.accent)
                    }
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18, style: .continuous))
                .sheet(isPresented: $isEditing) {
                    NavigationStack {
                        Form {
                            Section {
                                TextField("Eingang", text: $seat.entrance)
                                TextField("Block / Rang", text: $seat.block)
                                TextField("Reihe", text: $seat.row)
                                TextField("Platz", text: $seat.seat)
                            } footer: { Text("Bleibt nur auf diesem Gerät.") }
                        }
                        .navigationTitle("Sitzplatz")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Fertig") {
                                    SharedSeatStore.save(seat, forSlug: event.slug)
                                    Haptics.confirm()
                                    isEditing = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
        }
        .task(id: event.id) {
            seat = SharedSeatStore.seat(forSlug: event.slug) ?? ConcertSeat()
            guard let venueID = detail.object("venues")?.string("id"), let client = SocialStore.shared.repository?.client else { return }
            let rows: [JSONObject]? = try? await client.get(table: "venues", queryItems: [
                URLQueryItem(name: "select", value: "seating_plan_url"),
                URLQueryItem(name: "id", value: "eq.\(venueID)")
            ])
            seatingPlanURL = rows?.first?.string("seating_plan_url").flatMap(URL.init(string:))
        }
    }
}
