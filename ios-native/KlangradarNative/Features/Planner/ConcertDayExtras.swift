// Erstellt von Claude Code (Nutzerwunsch 26.10.2026): Ergänzungen der
// Konzertseite – Kurzporträts von Dirigent:in/Solist:innen für "In 3 Minuten
// vorbereitet", Hinweis auf Besetzungsänderungen und eigener Sitzplatz.
import PhotosUI
import SwiftUI
import PassKit
import VisionKit

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

    // Kompakte Zeile (06.11.2026): ein Symbol, Titel, eine Statuszeile.
    // Apple Wallet liegt jetzt im geöffneten Blatt statt als großer Knopf hier.
    private var tile: some View {
        HStack(spacing: 12) {
            Group {
                if let ticketImage {
                    Image(uiImage: ticketImage).resizable().scaledToFill()
                } else {
                    Image(systemName: "ticket").font(.body.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(KlangradarTheme.accent.opacity(0.12))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ticket & Platz").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(statusText).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if ticketImage != nil || !seat.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("Hinterlegen").font(.footnote.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16))
    }

    private var statusText: String {
        switch (ticketImage != nil, seat.isEmpty) {
        case (false, true): return "Noch nichts hinterlegt"
        case (true, true): return "Ticket hinterlegt · Platz fehlt"
        case (false, false): return seat.summary
        case (true, false): return "Ticket · \(seat.summary)"
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
    @State private var walletPass: WalletPassItem?
    @State private var walletError: String?
    @State private var isLoadingWallet = false
    @State private var ticketCode: TicketStore.TicketCode?
    @State private var showsScanner = false
    @State private var showsCodeEntry = false
    @State private var manualCode = ""
    @State private var showsSeatingPlan = false

    var body: some View {
        NavigationStack {
            // 07.11.2026 (Redesign): oben eine Vorschau im Stil der Wallet-
            // Karte (Konzertbild, Termin, Platz, Code), darunter klar
            // getrennte Bereiche Ticket, Platz, Saalplan, Wallet.
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    passPreview
                    ticketSection
                    seatSection
                    if let seatingPlanURL {
                        if !["jpg", "jpeg", "png", "webp"].contains(seatingPlanURL.pathExtension.lowercased()) {
                            Link(destination: seatingPlanURL) { rowLabel("Mein Platz im Saalplan", systemImage: "square.grid.3x3.topleft.filled") }
                                .buttonStyle(.plain)
                        } else {
                            Button { showsSeatingPlan = true } label: { rowLabel("Mein Platz im Saalplan", systemImage: "square.grid.3x3.topleft.filled") }
                                .buttonStyle(.plain)
                        }
                    }
                    if PKAddPassesViewController.canAddPasses() {
                        VStack(spacing: 8) {
                            AddToWalletButton { Task { await loadWalletPass() } }
                                .frame(height: 46)
                                .frame(maxWidth: .infinity)
                                .opacity(isLoadingWallet ? 0.5 : 1)
                                .accessibilityLabel("Zu Apple Wallet hinzufügen")
                            Text(walletError ?? (ticketCode != nil
                                 ? "Wallet-Karte mit Konzertbild, Platz und dem Code aus deinem Ticket."
                                 : "Wallet-Karte mit Konzertbild, Termin und Platz für den Sperrbildschirm."))
                                .font(.footnote).foregroundStyle(walletError == nil ? Color.secondary : Color.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(KlangradarTheme.pagePadding)
                .padding(.bottom, 30)
            }
            .background(Color(uiColor: .systemGroupedBackground))
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
            .sheet(isPresented: $showsScanner) {
                TicketCodeScanner { code in
                    TicketStore.saveCode(code, for: event.id); ticketCode = code; showsScanner = false; Haptics.confirm()
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsSeatingPlan) {
                if let seatingPlanURL { SeatingPlanSheet(url: seatingPlanURL, seat: seat, title: event.venueName) }
            }
            .alert("Code einfügen", isPresented: $showsCodeEntry) {
                TextField("Inhalt des QR-Codes", text: $manualCode)
                Button("Speichern") {
                    let value = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    let code = value.isEmpty ? nil : TicketStore.TicketCode(payload: value, format: "qr")
                    TicketStore.saveCode(code, for: event.id); ticketCode = code
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text("Zum Beispiel die Ticketnummer oder den Text hinter dem QR-Code aus der Bestätigungsmail.") }
            .sheet(item: $walletPass) { item in
                AddPassSheet(pass: item.pass).ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showsTicket) {
                if let image = ticketCode.flatMap({ TicketStore.render($0) }) ?? ticketImage {
                    TicketFullScreen(image: image) { showsTicket = false } onRemove: {
                        TicketStore.remove(for: event.id); self.ticketImage = nil; showsTicket = false
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            ticketCode = TicketStore.code(for: event.id)
            // Ältere Tickets ohne gespeicherten Code einmal nachträglich prüfen.
            if ticketCode == nil, let ticketImage, let code = await TicketStore.detectCode(in: ticketImage) {
                TicketStore.saveCode(code, for: event.id)
                ticketCode = code
            }
        }
    }

    @ViewBuilder private var pickerButtons: some View {
        Button("Foto oder Screenshot wählen", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
        Button("PDF oder Datei wählen", systemImage: "doc") { showsFileImporter = true }
    }

    private func store(_ image: UIImage) {
        TicketStore.save(image, for: event.id)
        ticketImage = image
        Haptics.confirm()
        Task {
            let code = await TicketStore.detectCode(in: image)
            TicketStore.saveCode(code, for: event.id)
            ticketCode = code
        }
    }

    // MARK: Bausteine (07.11.2026)

    private var dateLine: String {
        guard let start = event.startDate else { return "" }
        return KlangradarDateTime.string(start, format: "EEEE, d. MMMM · HH:mm")
    }

    private var passPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedAsyncImage(url: event.primaryImageURL, maxPixel: 900) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { LinearGradient(colors: [KlangradarTheme.accent, .black], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                LinearGradient(colors: [.clear, Color(red: 0.086, green: 0.078, blue: 0.118)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 60).frame(maxWidth: .infinity).allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(.white).lineLimit(3)
                    Text(dateLine).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    Text(event.venueName).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                HStack(spacing: 0) {
                    passField("EINGANG", seat.entrance)
                    passField("BLOCK", seat.block)
                    passField("REIHE", seat.row)
                    passField("PLATZ", seat.seat)
                }
                // Perforation wie bei einer Eintrittskarte
                PerforationLine().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.white.opacity(0.25)).frame(height: 1)
                Button { if ticketImage != nil || ticketCode != nil { showsTicket = true } else { showsPhotoPicker = true } } label: {
                    HStack(spacing: 14) {
                        Group {
                            if let code = ticketCode, let rendered = TicketStore.render(code, scale: 6) {
                                Image(uiImage: rendered).interpolation(.none).resizable().scaledToFit().padding(6).background(.white)
                            } else if let ticketImage {
                                Image(uiImage: ticketImage).resizable().scaledToFill()
                            } else {
                                Image(systemName: "qrcode").font(.title2).foregroundStyle(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.08))
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ticketImage == nil && ticketCode == nil ? "Ticket hinzufügen" : "Ticket öffnen")
                                .font(.headline).foregroundStyle(.white)
                            Text(ticketStatus).font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
        .background(Color(red: 0.086, green: 0.078, blue: 0.118))
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var ticketStatus: String {
        if let code = ticketCode { return "\(code.format.uppercased())-Code erkannt · scharf für den Einlass" }
        if ticketImage != nil { return "Foto hinterlegt · volle Helligkeit beim Öffnen" }
        return "Foto, Screenshot oder PDF – bleibt auf deinem iPhone"
    }

    private func passField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Color(red: 0.77, green: 0.67, blue: 0.47))
            Text(value.isEmpty ? "–" : value).font(.headline).foregroundStyle(.white).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var ticketSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Ticket")
            if ticketImage == nil {
                HStack(spacing: 10) {
                    bigTile("Foto oder\nScreenshot", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
                    bigTile("PDF oder\nDatei", systemImage: "doc.richtext") { showsFileImporter = true }
                }
            }
            // Code direkt hinterlegen (07.11.2026): mit der Kamera vom Papier-
            // oder Bildschirmticket scannen oder als Text einfügen.
            VStack(spacing: 0) {
                if DataScannerViewController.isSupported {
                    Button { showsScanner = true } label: { rowLabel(ticketCode == nil ? "Code mit der Kamera scannen" : "Code neu scannen", systemImage: "qrcode.viewfinder") }
                        .buttonStyle(.plain)
                    Divider().padding(.leading, 48)
                }
                Button { manualCode = ticketCode?.payload ?? ""; showsCodeEntry = true } label: { rowLabel("Code als Text einfügen", systemImage: "text.cursor") }
                    .buttonStyle(.plain)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
            if ticketImage != nil || ticketCode != nil {
                VStack(spacing: 0) {
                    Menu { pickerButtons } label: { rowLabel("Ticket ersetzen", systemImage: "arrow.triangle.2.circlepath") }
                    Divider().padding(.leading, 48)
                    Button(role: .destructive) {
                        TicketStore.remove(for: event.id); TicketStore.saveCode(nil, for: event.id); ticketImage = nil; ticketCode = nil
                    } label: { rowLabel("Ticket entfernen", systemImage: "trash", tint: .red) }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var seatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Platz")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                seatField("Eingang", text: $seat.entrance)
                seatField("Block / Rang", text: $seat.block)
                seatField("Reihe", text: $seat.row)
                seatField("Platz", text: $seat.seat)
            }
            Text("Erscheint am Konzerttag auf dem Sperrbildschirm und in der Live-Aktivität.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func seatField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("–", text: text).font(.title3.weight(.semibold)).textInputAutocapitalization(.characters)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.weight(.semibold))
    }

    private func bigTile(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(KlangradarTheme.accent)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, systemImage: String, tint: Color = KlangradarTheme.accent) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).foregroundStyle(tint).frame(width: 22)
            Text(title).foregroundStyle(tint == .red ? .red : .primary)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(tint == .red ? Color.clear : Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Apple Wallet (02.11.2026)

private struct WalletPassItem: Identifiable {
    let id = UUID()
    let pass: PKPass
}

extension TicketSeatEditor {
    @MainActor
    fileprivate func loadWalletPass() async {
        isLoadingWallet = true
        defer { isLoadingWallet = false }
        walletError = nil
        guard let client = SocialStore.shared.repository?.client else { walletError = "Wallet ist gerade nicht verfügbar."; return }
        let items = [URLQueryItem(name: "slug", value: event.slug),
                     URLQueryItem(name: "entrance", value: seat.entrance), URLQueryItem(name: "block", value: seat.block),
                     URLQueryItem(name: "row", value: seat.row), URLQueryItem(name: "seat", value: seat.seat)]
            + (ticketCode.map { [URLQueryItem(name: "code", value: $0.payload), URLQueryItem(name: "format", value: $0.format)] } ?? [])
        do {
            let data = try await client.edgeFunctionData("wallet-pass", queryItems: items, accessToken: SocialStore.shared.token)
            walletPass = WalletPassItem(pass: try PKPass(data: data))
        } catch {
            walletError = "Die Wallet-Karte konnte nicht erstellt werden."
        }
    }
}

/// Offizieller „Zu Apple Wallet hinzufügen“-Knopf.
private struct AddToWalletButton: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }
    func updateUIView(_ uiView: PKAddPassButton, context: Context) { context.coordinator.action = action }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

private struct AddPassSheet: UIViewControllerRepresentable {
    let pass: PKPass
    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}


/// Gestrichelte Trennlinie (Perforation) in der Ticket-Vorschau.
private struct PerforationLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}


/// Kamera-Scanner für Ticket-Codes (VisionKit, iOS 16+).
private struct TicketCodeScanner: UIViewControllerRepresentable {
    let onFound: (TicketStore.TicketCode) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr, .aztec, .pdf417, .code128])],
            qualityLevel: .accurate, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (TicketStore.TicketCode) -> Void
        private var done = false
        init(onFound: @escaping (TicketStore.TicketCode) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                let format: String
                switch barcode.observation.symbology {
                case .aztec: format = "aztec"
                case .pdf417: format = "pdf417"
                case .code128: format = "code128"
                default: format = "qr"
                }
                done = true
                dataScanner.stopScanning()
                onFound(TicketStore.TicketCode(payload: payload, format: format))
                return
            }
        }
    }
}

/// Saalplan mit Zoom und dem eigenen Platz als Hinweis (07.11.2026).
/// Später: Platz direkt im Plan markieren, sobald Pläne Koordinaten haben.
private struct SeatingPlanSheet: View {
    let url: URL
    let seat: ConcertSeat
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !seat.isEmpty {
                    Label(seat.summary, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KlangradarTheme.accent.opacity(0.1))
                }
                ScrollView([.horizontal, .vertical]) {
                    CachedAsyncImage(url: url, maxPixel: 2400) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
                    }
                    .frame(width: UIScreen.main.bounds.width * scale * pinch)
                    .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) })
                    .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
                }
            }
            .navigationTitle("Saalplan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
