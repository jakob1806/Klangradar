// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Ergänzungen der
// Konzertseite – Kurzporträts von Dirigent:in/Solist:innen für "In 3 Minuten
// vorbereitet", Hinweis auf Besetzungsänderungen und eigener Sitzplatz.
import PhotosUI
import SwiftUI

/// Wer steht auf der Bühne? Zwei Sätze aus der Biografie plus aktuelle Position.
struct PerformerBriefs: View {
    let detail: JSONObject

    struct Brief: Identifiable {
        let id: UUID
        var isEnsemble = false
        let name: String
        let role: String?
        let photoURL: URL?
        let route: EntityRoute?
        let text: String
        let fullText: String
    }

    @State private var briefs: [Brief] = []
    @State private var expanded: Set<UUID> = []

    struct Candidate: Equatable {
        let id: UUID
        let isEnsemble: Bool
        let role: String?
    }

    /// Alle Mitwirkenden (Personen und Ensembles), ohne Doppelungen.
    static func allCandidates(_ detail: JSONObject) -> [Candidate] {
        var seen = Set<UUID>()
        return detail.objects("event_participants").compactMap { row -> Candidate? in
            let role = row.string("role_label") ?? row.string("role")
            if let id = row.object("persons")?.string("id").flatMap(UUID.init(uuidString:)), seen.insert(id).inserted {
                return Candidate(id: id, isEnsemble: false, role: role)
            }
            if let id = row.object("ensembles")?.string("id").flatMap(UUID.init(uuidString:)), seen.insert(id).inserted {
                return Candidate(id: id, isEnsemble: true, role: role ?? "Ensemble")
            }
            return nil
        }
    }

    /// Nutzerwunsch 27.10.2026: Bei bis zu 4 Mitwirkenden stehen ALLE hier
    /// mit Kurzbiografie und die Liste "Mitwirkende" entfällt (sonst doppelt).
    static func replacesParticipantList(_ detail: JSONObject) -> Bool {
        (1...4).contains(allCandidates(detail).count)
    }

    private var candidates: [Candidate] {
        Self.replacesParticipantList(detail) ? Self.allCandidates(detail) : []
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
                                .frame(width: 40, height: 40).clipShape(brief.isEnsemble ? AnyShape(.rect(cornerRadius: 10)) : AnyShape(.circle))
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
                                .font(.footnote).foregroundStyle(brief.fullText.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(0.85)))
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
        let personIDs = list.filter { !$0.isEnsemble }.map(\.id.uuidString)
        let ensembleIDs = list.filter(\.isEnsemble).map(\.id.uuidString)
        async let personRows: [JSONObject] = personIDs.isEmpty ? [] : ((try? await client.get(table: "persons", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,full_name,photo_url,biography_de,instrument"),
            URLQueryItem(name: "id", value: "in.(\(personIDs.joined(separator: ",")))")
        ])) ?? [])
        async let ensembleRows: [JSONObject] = ensembleIDs.isEmpty ? [] : ((try? await client.get(table: "ensembles", queryItems: [
            URLQueryItem(name: "select", value: "id,slug,name,photo_url,description_de"),
            URLQueryItem(name: "id", value: "in.(\(ensembleIDs.joined(separator: ",")))")
        ])) ?? [])
        let rows = await personRows + ensembleRows
        let byID = Dictionary(rows.compactMap { row in row.string("id").flatMap(UUID.init(uuidString:)).map { ($0, row) } }, uniquingKeysWith: { a, _ in a })
        briefs = list.compactMap { candidate in
            guard let row = byID[candidate.id], let name = row.string(candidate.isEnsemble ? "name" : "full_name") else { return nil }
            let bio = (row.string(candidate.isEnsemble ? "description_de" : "biography_de") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Nur die Biografie: current_roles_de enthält teils redaktionelle
            // Prüfvermerke ("… saisonbezogen prüfen").
            let full = Self.withoutEditorialNotes(bio)
            // Fehlt die Biografie noch, bleibt die Person trotzdem sichtbar –
            // die Hintergrund-Recherche (KI + Wikipedia) ergänzt sie.
            let short = full.isEmpty ? "Kurzbiografie wird gerade recherchiert." : Self.firstSentences(full, count: 2)
            return Brief(id: candidate.id, isEnsemble: candidate.isEnsemble, name: name, role: Self.roleLabel(candidate.role ?? row.string("instrument")),
                         photoURL: row.string("photo_url").flatMap(URL.init(string:)),
                         route: EntityRoute(kind: candidate.isEnsemble ? .ensemble : .person, identifier: row.string("slug") ?? candidate.id.uuidString),
                         text: short, fullText: full)
        }
    }

    /// "dirigent" → "Dirigent" (Rollen kommen teils kleingeschrieben).
    static func roleLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// Importierte Biografien enthalten teils interne Vermerke wie
    /// "Amtsstatus und Gasttermine saisonbezogen prüfen" – solche Sätze weg.
    static func withoutEditorialNotes(_ text: String) -> String {
        var kept: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            let parts = sentence.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.range(of: #"\b(prüfen|verifizieren|TODO|klären)\b"#, options: [.regularExpression, .caseInsensitive]) == nil && !$0.isEmpty }
            if !parts.isEmpty { kept.append(parts.joined(separator: "; ")) }
        }
        return kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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

/// "Ticket & Platz" (Nutzerwunsch 27.10.2026): eine einzige Kachel. Sie
/// zeigt, ob ein Ticket hinterlegt und ein Platz eingetragen ist; ein Tipp
/// öffnet alles zusammen (Ticket ablegen/öffnen, Platz, Saalplan). Beides
/// bleibt nur auf dem Gerät.
struct SeatCard: View {
    let event: ConcertEvent
    let detail: JSONObject
    @State private var seat = ConcertSeat()
    @State private var ticketImage: UIImage?
    @State private var seatingPlanURL: URL?
    @State private var isEditing = false

    private var isUpcoming: Bool { (event.startDate ?? .distantPast).addingTimeInterval(3 * 3600) > .now }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUpcoming {
                Button { isEditing = true } label: { tile }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ticket und Platz: \(ticketImage == nil ? "kein Ticket" : "Ticket hinterlegt"), \(seat.isEmpty ? "kein Platz" : seat.summary)")
                    .sheet(isPresented: $isEditing, onDismiss: { SharedSeatStore.save(seat, forSlug: event.slug) }) {
                        TicketSeatEditor(event: event, seat: $seat, ticketImage: $ticketImage, seatingPlanURL: seatingPlanURL)
                    }
            }
        }
        .task(id: event.id) {
            seat = SharedSeatStore.seat(forSlug: event.slug) ?? ConcertSeat()
            ticketImage = TicketStore.image(for: event.id)
            guard let venueID = detail.object("venues")?.string("id"), let client = SocialStore.shared.repository?.client else { return }
            let rows: [JSONObject]? = try? await client.get(table: "venues", queryItems: [
                URLQueryItem(name: "select", value: "seating_plan_url"),
                URLQueryItem(name: "id", value: "eq.\(venueID)")
            ])
            seatingPlanURL = rows?.first?.string("seating_plan_url").flatMap(URL.init(string:))
        }
    }

    private var tile: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                if let ticketImage {
                    Image(uiImage: ticketImage).resizable().scaledToFill()
                        .frame(width: 58, height: 58).clipShape(.rect(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "ticket").font(.title2).foregroundStyle(KlangradarTheme.accent)
                        .frame(width: 58, height: 58)
                        .background(KlangradarTheme.accent.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
                }
                if ticketImage != nil {
                    Image(systemName: "checkmark.circle.fill").font(.body).foregroundStyle(.white, .green)
                        .background(Circle().fill(.white).padding(2)).offset(x: 6, y: 6)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Ticket & Platz").font(.headline).foregroundStyle(.primary)
                statusLine(ticketImage != nil ? "Ticket hinterlegt" : "Noch kein Ticket hinterlegt", symbol: "ticket.fill", done: ticketImage != nil)
                statusLine(seat.isEmpty ? "Platz noch nicht eingetragen" : seat.summary, symbol: "chair.fill", done: !seat.isEmpty)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
        .contentShape(.rect(cornerRadius: 20))
    }

    private func statusLine(_ text: String, symbol: String, done: Bool) -> some View {
        Label {
            Text(text).font(.subheadline.weight(done ? .semibold : .regular)).foregroundStyle(done ? .primary : .secondary).lineLimit(2)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : symbol).font(.caption).foregroundStyle(done ? .green : .secondary).frame(width: 18)
        }
    }
}

/// Alles zu Ticket und Platz in einem Blatt.
private struct TicketSeatEditor: View {
    let event: ConcertEvent
    @Binding var seat: ConcertSeat
    @Binding var ticketImage: UIImage?
    let seatingPlanURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var ticketPick: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false
    @State private var showsTicket = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let ticketImage {
                        Button { showsTicket = true } label: {
                            Image(uiImage: ticketImage).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 220)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button("Ticket öffnen (volle Helligkeit)", systemImage: "qrcode.viewfinder") { showsTicket = true }
                            .fontWeight(.semibold)
                        Menu { pickerButtons } label: { Label("Ticket ersetzen", systemImage: "arrow.triangle.2.circlepath") }
                        Button("Ticket entfernen", systemImage: "trash", role: .destructive) {
                            TicketStore.remove(for: event.id); self.ticketImage = nil
                        }
                    } else {
                        pickerButtons
                    }
                } header: { Text("Ticket") } footer: { Text("Foto, Screenshot oder PDF – bleibt nur auf deinem iPhone.") }

                Section {
                    TextField("Eingang", text: $seat.entrance)
                    TextField("Block / Rang", text: $seat.block)
                    TextField("Reihe", text: $seat.row)
                    TextField("Platz", text: $seat.seat)
                } header: { Text("Platz") } footer: { Text("Erscheint am Konzerttag auf dem Sperrbildschirm und in der Live-Aktivität.") }

                if let seatingPlanURL {
                    Section {
                        Link(destination: seatingPlanURL) { Label("Saalplan ansehen", systemImage: "square.grid.3x3.topleft.filled") }
                    }
                }
            }
            .navigationTitle("Ticket & Platz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        SharedSeatStore.save(seat, forSlug: event.slug)
                        Haptics.confirm()
                        dismiss()
                    }
                }
            }
            .photosPicker(isPresented: $showsPhotoPicker, selection: $ticketPick, matching: .images)
            .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .image]) { result in
                guard case let .success(url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let image = TicketStore.image(from: url) { store(image) }
            }
            .onChange(of: ticketPick) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { store(image) }
                    ticketPick = nil
                }
            }
            .fullScreenCover(isPresented: $showsTicket) {
                if let ticketImage {
                    TicketFullScreen(image: ticketImage) { showsTicket = false } onRemove: {
                        TicketStore.remove(for: event.id); self.ticketImage = nil; showsTicket = false
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private var pickerButtons: some View {
        Button("Foto oder Screenshot wählen", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
        Button("PDF oder Datei wählen", systemImage: "doc") { showsFileImporter = true }
    }

    private func store(_ image: UIImage) {
        TicketStore.save(image, for: event.id)
        ticketImage = image
        Haptics.confirm()
    }
}
