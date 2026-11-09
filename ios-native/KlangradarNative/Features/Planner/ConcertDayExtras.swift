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

/// Ticketbereich auf der Konzertseite (Redesign 08.11.2026):
/// 1. ohne Ticket eine schmale Einladung, mit Ticket eine kleine Eintrittskarte
///    im Stil der Wallet-Karte (Platz groß, Abriss, Mini-Code),
/// 2. am Konzerttag ganz oben mit „Ticket öffnen“, Einlass und Eingang,
/// 3. Wallet-Status direkt auf der Karte,
/// 4. mehrere Tickets: Anzahl und „Ticket weitergeben“,
/// 5. nach dem Konzert eine Erinnerung mit Weg ins Konzerttagebuch.
struct SeatCard: View {
    enum Placement { case inline, concertDay }

    let event: ConcertEvent
    let detail: JSONObject
    var placement: Placement = .inline
    @State private var seat = ConcertSeat()
    @State private var ticketImage: UIImage?
    @State private var codes: [TicketStore.TicketCode] = []
    @State private var seatingPlanURL: URL?
    @State private var isEditing = false
    @State private var showsTicket = false
    @State private var showsJournal = false
    @State private var inWallet = false

    private static let ink = Color(red: 0.102, green: 0.106, blue: 0.180)
    private static let mint = Color(red: 0.322, green: 0.804, blue: 0.737)
    private static let periwinkle = Color(red: 0.443, green: 0.502, blue: 0.984)

    private var start: Date? { event.startDate }
    private var isPast: Bool { (start ?? .distantFuture).addingTimeInterval(3 * 3600) < .now }
    private var hasTicket: Bool { ticketImage != nil || !codes.isEmpty }

    static func isConcertDay(_ event: ConcertEvent) -> Bool {
        guard let start = event.startDate else { return false }
        return KlangradarDateTime.calendar.isDateInToday(start) && start.addingTimeInterval(3 * 3600) > .now
    }

    var body: some View {
        Group {
            if isPast {
                if hasTicket || !seat.isEmpty { memoryCard }
            } else if placement == .concertDay {
                concertDayCard
            } else if Self.isConcertDay(event) {
                EmptyView() // steht am Konzerttag oben
            } else if hasTicket || !seat.isEmpty {
                ticketCard
            } else {
                inviteRow
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: reload) {
            TicketSeatEditor(event: event, seat: $seat, ticketImage: $ticketImage, seatingPlanURL: seatingPlanURL)
        }
        .fullScreenCover(isPresented: $showsTicket) {
            let images = codes.compactMap { TicketStore.render($0) }
            let all = images.isEmpty ? [ticketImage].compactMap { $0 } : images
            // Mehrere Tickets: seitlich wischen.
            TabView {
                ForEach(Array(all.enumerated()), id: \.offset) { _, image in
                    TicketFullScreen(image: image) { showsTicket = false } onRemove: {
                        TicketStore.remove(for: event.id); TicketStore.saveCodes([], for: event.id); showsTicket = false; reload()
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: all.count > 1 ? .always : .never))
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsJournal) {
            NavigationStack {
                ConcertJournalEditor(existing: ConcertJournalEntry(title: event.title, startsAt: start ?? .now,
                                                                   note: seat.isEmpty ? "" : "Platz: \(seat.summary)"))
            }
        }
        .task(id: event.id) {
            reload()
            guard let venueID = detail.object("venues")?.string("id"), let client = SocialStore.shared.repository?.client else { return }
            let rows: [JSONObject]? = try? await client.get(table: "venues", queryItems: [
                URLQueryItem(name: "select", value: "seating_plan_url"),
                URLQueryItem(name: "id", value: "eq.\(venueID)")
            ])
            seatingPlanURL = rows?.first?.string("seating_plan_url").flatMap(URL.init(string:))
        }
    }

    private func reload() {
        seat = SharedSeatStore.seat(forSlug: event.slug) ?? ConcertSeat()
        ticketImage = TicketStore.image(for: event.id)
        codes = TicketStore.codes(for: event.id)
        inWallet = WalletStatus.isAdded(eventID: event.id)
        SharedSeatStore.save(seat, forSlug: event.slug)
    }

    // MARK: 1a – Einladung ohne Ticket

    private var inviteRow: some View {
        Button { isEditing = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.ink)
                    Image(systemName: "ticket").font(.body.weight(.semibold)).foregroundStyle(Self.mint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ticket hinterlegen").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Am Abend mit einem Tipp am Einlass").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(KlangradarTheme.accent)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ticket hinterlegen")
    }

    // MARK: 1b – Mini-Eintrittskarte

    private var ticketCard: some View {
        Button { isEditing = true } label: {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    KlangradarMark(stem: .white).frame(width: 16, height: 19)
                    Text("Dein Ticket").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    walletBadge
                }
                .padding(.horizontal, 16).padding(.top, 14)
                HStack(alignment: .bottom, spacing: 0) {
                    seatColumns
                    Spacer(minLength: 12)
                    miniCode
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 14)
                tearLine
                footer
            }
            .background(Self.ink, in: EntryTicketShape(tearFromBottom: 52))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dein Ticket, \(seat.isEmpty ? "kein Platz eingetragen" : seat.summary). Zum Bearbeiten tippen.")
    }

    private var seatColumns: some View {
        HStack(alignment: .top, spacing: 18) {
            if seat.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PLATZ").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Self.mint)
                    Text("Platz eintragen").font(.headline).foregroundStyle(.white.opacity(0.7))
                }
            } else {
                ForEach(seatParts, id: \.0) { label, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Self.mint)
                        Text(value).font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    private var seatParts: [(String, String)] {
        seat.parts.map { ($0.label.uppercased(), $0.value) }
    }

    private var entranceTitle: String {
        (seat.entranceLabel.isEmpty ? ConcertSeat.defaultLabels.entrance : seat.entranceLabel).uppercased()
    }

    @ViewBuilder private var miniCode: some View {
        if let code = codes.first, let rendered = TicketStore.render(code, scale: 4) {
            Image(uiImage: rendered).interpolation(.none).resizable().scaledToFit()
                .padding(5).frame(width: 58, height: 58)
                .background(.white, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        } else if let ticketImage {
            Image(uiImage: ticketImage).resizable().scaledToFill()
                .frame(width: 58, height: 58).clipShape(.rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var tearLine: some View {
        PerforationLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            .foregroundStyle(.white.opacity(0.22))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if codes.count > 1 {
                Label("\(codes.count) Tickets", systemImage: "person.2.fill").font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                if let second = codes.dropFirst().first, let image = TicketStore.render(second, scale: 10) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Ticket für \(event.title)", image: Image(uiImage: image))) {
                        Text("Weitergeben").font(.footnote.weight(.semibold)).foregroundStyle(Self.mint)
                    }
                }
            } else {
                Text(hasTicket ? "Am Einlass: Karte antippen" : "Ticket fehlt noch").font(.footnote).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if hasTicket {
                Button { showsTicket = true } label: {
                    Text("Öffnen").font(.footnote.weight(.semibold)).foregroundStyle(Self.ink)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var walletBadge: some View {
        if inWallet {
            Label("In Wallet", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold))
                .foregroundStyle(Self.mint)
        }
    }

    // MARK: 2 – Konzerttag

    private var concertDayCard: some View {
        let times = start.map { ConcertTimes.compute(start: $0, detail: detail) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                KlangradarMark(stem: .white).frame(width: 16, height: 19)
                Text("HEUTE ABEND").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Self.mint)
                Spacer()
                walletBadge
            }
            .padding(.horizontal, 18).padding(.top, 16)
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                if let doors = times?.doorsAt {
                    timeColumn("EINLASS", doors, estimated: times?.doorsEstimated ?? true)
                }
                if let start { timeColumn("BEGINN", start, estimated: false) }
                if !seat.entrance.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entranceTitle).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Self.mint)
                        Text(seat.entrance).font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 14)
            if !seatParts.filter({ $0.0 != entranceTitle }).isEmpty {
                Text(seatParts.filter { $0.0 != entranceTitle }.map { $0.0 == "BEREICH" ? $0.1 : "\($0.0.capitalized) \($0.1)" }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 18).padding(.top, 8)
            }
            tearLine.padding(.top, 16)
            HStack(spacing: 10) {
                if hasTicket {
                    Button { showsTicket = true } label: {
                        Label(codes.count > 1 ? "Tickets öffnen" : "Ticket öffnen", systemImage: "qrcode")
                            .font(.headline).foregroundStyle(Self.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { isEditing = true } label: {
                        Label("Ticket hinterlegen", systemImage: "plus").font(.headline).foregroundStyle(Self.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button { isEditing = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.headline).foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ticket und Platz bearbeiten")
            }
            .padding(14)
        }
        .background(Self.ink, in: EntryTicketShape(tearFromBottom: 78))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }

    private func timeColumn(_ label: String, _ date: Date, estimated: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Self.mint)
            Text((estimated ? "ca. " : "") + KlangradarDateTime.string(date, format: "HH:mm"))
                .font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    // MARK: 5 – Erinnerung

    private var memoryCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Self.periwinkle.opacity(0.15))
                Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(Self.periwinkle)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Du warst hier").font(.subheadline.weight(.semibold))
                Text(seat.isEmpty ? (start.map { KlangradarDateTime.string($0, format: "d. MMMM yyyy") } ?? "") : seat.summary)
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { showsJournal = true } label: {
                Text("Ins Tagebuch").font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// Eintrittskarten-Umriss: abgerundet, seitliche Aussparungen am Abriss.
struct EntryTicketShape: Shape {
    /// Abstand des Abrisses vom unteren Rand.
    var tearFromBottom: CGFloat = 52
    func path(in rect: CGRect) -> Path {
        let notch: CGFloat = 9
        let y = rect.maxY - tearFromBottom
        let base = Path(roundedRect: rect, cornerRadius: 20, style: .continuous)
        var notches = Path()
        notches.addEllipse(in: CGRect(x: rect.minX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        notches.addEllipse(in: CGRect(x: rect.maxX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        return base.subtracting(notches)
    }
}

/// Das Klangradar-K aus dem App-Icon als Vektor.
struct KlangradarMark: View {
    var stem: Color = .primary
    var body: some View {
        Canvas { context, size in
            let s = min(size.width / 630, size.height / 765)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 200) * s, y: (y - 130) * s) }
            var upper = Path()
            upper.move(to: p(366, 392)); upper.addLine(to: p(696, 160)); upper.addLine(to: p(782, 280))
            upper.addLine(to: p(452, 512)); upper.addLine(to: p(366, 512)); upper.closeSubpath()
            // Kreise einzeln füllen: im selben Pfad heben sich gegenläufige
            // Umläufe auf und hinterlassen ein Loch (schwarzer Fleck).
            let blue = Color(red: 0.443, green: 0.502, blue: 0.984)
            context.fill(upper, with: .color(blue))
            context.fill(Path(ellipseIn: CGRect(origin: p(665, 145), size: CGSize(width: 148 * s, height: 148 * s))), with: .color(blue))
            var lower = Path()
            lower.move(to: p(366, 632)); lower.addLine(to: p(696, 864)); lower.addLine(to: p(782, 744))
            lower.addLine(to: p(452, 512)); lower.addLine(to: p(366, 512)); lower.closeSubpath()
            let mint = Color(red: 0.322, green: 0.804, blue: 0.737)
            context.fill(lower, with: .color(mint))
            context.fill(Path(ellipseIn: CGRect(origin: p(665, 731), size: CGSize(width: 148 * s, height: 148 * s))), with: .color(mint))
            context.fill(Path(roundedRect: CGRect(origin: p(218, 192), size: CGSize(width: 148 * s, height: 640 * s)), cornerRadius: 74 * s), with: .color(stem))
        }
        .accessibilityHidden(true)
    }
}

/// Merkt sich, ob die Wallet-Karte eines Konzerts hinzugefügt wurde.
enum WalletStatus {
    private static func key(_ id: UUID) -> String { "walletAdded.\(id.uuidString.lowercased())" }
    static func isAdded(eventID: UUID) -> Bool { UserDefaults.standard.bool(forKey: key(eventID)) }
    static func refresh(eventID: UUID) {
        let prefix = eventID.uuidString.lowercased()
        let found = PKPassLibrary().passes().contains { $0.serialNumber.lowercased().hasPrefix(prefix) }
        UserDefaults.standard.set(found, forKey: key(eventID))
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
    @State private var ticketCodes: [TicketStore.TicketCode] = []
    @State private var openCodeIndex = 0
    @State private var detectionNote: String?
    private var ticketCode: TicketStore.TicketCode? { ticketCodes.first }
    @State private var showsScanner = false
    @State private var showsCodeEntry = false
    @State private var manualCode = ""
    @State private var showsSeatingPlan = false
    @State private var stripImage: UIImage?
    @State private var stripFocus = CGPoint(x: 0.5, y: 0.35)

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
                                .frame(width: 240, height: 44)
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
                // 08.11.2026: alle Seiten durchsuchen, nicht nur die erste.
                let pages = TicketStore.pages(from: url)
                if let first = pages.first { store(first, pages: pages) }
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
                    if !ticketCodes.contains(where: { $0.payload == code.payload }) { ticketCodes.append(code) }
                    TicketStore.saveCodes(ticketCodes, for: event.id); showsScanner = false; Haptics.confirm()
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsSeatingPlan) {
                if let seatingPlanURL { SeatingPlanSheet(url: seatingPlanURL, seat: seat, title: event.venueName, eventID: event.id) }
            }
            .alert("Code einfügen", isPresented: $showsCodeEntry) {
                TextField("Inhalt des QR-Codes", text: $manualCode)
                Button("Speichern") {
                    let value = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    let code = value.isEmpty ? nil : TicketStore.TicketCode(payload: value, format: "qr")
                    ticketCodes = code.map { [$0] } ?? []
                    TicketStore.saveCodes(ticketCodes, for: event.id)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text("Zum Beispiel die Ticketnummer oder den Text hinter dem QR-Code aus der Bestätigungsmail.") }
            .sheet(item: $walletPass, onDismiss: { WalletStatus.refresh(eventID: event.id) }) { item in
                AddPassSheet(passes: item.passes).ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showsTicket) {
                if let image = (ticketCodes.indices.contains(openCodeIndex) ? TicketStore.render(ticketCodes[openCodeIndex]) : nil) ?? ticketImage {
                    TicketFullScreen(image: image) { showsTicket = false } onRemove: {
                        TicketStore.remove(for: event.id); self.ticketImage = nil; showsTicket = false
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task(id: walletImageURL) { await loadStripImage() }
        .task {
            ticketCodes = TicketStore.codes(for: event.id)
            // Ältere Tickets ohne gespeicherten Code einmal nachträglich prüfen.
            if ticketCodes.isEmpty, let ticketImage {
                ticketCodes = await TicketStore.detectCodes(in: [ticketImage])
                TicketStore.saveCodes(ticketCodes, for: event.id)
            }
        }
    }

    @ViewBuilder private var pickerButtons: some View {
        Button("Foto oder Screenshot wählen", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
        Button("PDF oder Datei wählen", systemImage: "doc") { showsFileImporter = true }
    }

    private func store(_ image: UIImage, pages: [UIImage]? = nil) {
        TicketStore.save(image, for: event.id)
        ticketImage = image
        detectionNote = "Suche nach Codes …"
        Task {
            let codes = await TicketStore.detectCodes(in: pages ?? [image])
            // Platz aus dem Ticket übernehmen, nur leere Felder füllen.
            let found = await TicketStore.detectSeat(in: pages ?? [image])
            // 09.11.2026: neues Ticket → Erkanntes ersetzt alte Werte (auch
            // Fehlerkennungen früherer Versionen); nicht Erkanntes bleibt.
            if !found.isEmpty {
                if !found.entrance.isEmpty { seat.entrance = found.entrance; seat.entranceLabel = found.entranceLabel }
                if !found.block.isEmpty { seat.block = found.block; seat.blockLabel = found.blockLabel }
                if !found.row.isEmpty { seat.row = found.row; seat.rowLabel = found.rowLabel }
                if !found.seat.isEmpty { seat.seat = found.seat; seat.seatLabel = found.seatLabel }
                for extra in found.extras {
                    seat.extras.removeAll { $0.label == extra.label }
                    seat.extras.append(extra)
                }
            }
            if !found.isEmpty { SharedSeatStore.save(seat, forSlug: event.slug) }
            TicketStore.saveCodes(codes, for: event.id)
            ticketCodes = codes
            openCodeIndex = 0
            switch codes.count {
            case 0: detectionNote = "Kein Code erkannt – am Einlass wird dein Ticket als Bild gezeigt."
            case 1: detectionNote = "\(codes[0].format.uppercased())-Code erkannt und geprüft."
            default: detectionNote = "\(codes.count) Tickets erkannt – für jedes gibt es eine eigene Wallet-Karte."
            }
            Haptics.confirm()
        }
    }

    // MARK: Bausteine (07.11.2026)

    private var dateLine: String {
        guard let start = event.startDate else { return "" }
        return KlangradarDateTime.string(start, format: "EEEE, d. MMMM · HH:mm")
    }

    // 08.11.2026: Vorschau wie die echte Wallet-Karte (Nachtblau, Mint,
    // Klangradar-K; Konzertfoto oder Plakat-Titel), nur ausgefüllte Felder.
    private var passPreview: some View {
        let ink = Color(red: 0.102, green: 0.106, blue: 0.180)
        let mint = Color(red: 0.322, green: 0.804, blue: 0.737)
        let hasTicket = ticketImage != nil || ticketCode != nil
        let filled = seat.parts.map { ($0.label.uppercased(), $0.value) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                KlangradarMark(stem: .white).frame(width: 18, height: 22)
                Text("Klangradar").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                if let start = event.startDate {
                    Text(KlangradarDateTime.string(start, format: "EEE · HH:mm")).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16).frame(height: 50)
            // 08.11.2026: Bild in voller Größe ohne Zuschnitt, Titel darunter.
            // 09.11.2026 (Variante A): flacher Bildstreifen wie in Wallet
            // (375×98 pt-Verhältnis), Ausschnitt eher oben (Gesichter).
            // Ausschnitt folgt dem Motiv (Gesicht/Motiv erkannt) und lässt sich
            // mit dem Finger verschieben – die Wallet-Karte übernimmt ihn.
            Color.white.opacity(0.06)
                .frame(maxWidth: .infinity).aspectRatio(375.0 / 98.0, contentMode: .fit)
                .overlay {
                    if let stripImage {
                        FocusedStripImage(image: stripImage, focus: $stripFocus) { ImageFocus.store($0, for: event.id) }
                    } else if walletImageURL != nil {
                        ProgressView().tint(.white.opacity(0.6))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if stripImage != nil {
                        Label("Ziehen zum Verschieben", systemImage: "hand.draw")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: .capsule)
                            .padding(8).allowsHitTesting(false)
                    }
                }
                .clipped()
            Text(event.title)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .minimumScaleFactor(0.6).lineLimit(3)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.top, 14)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    previewField("DATUM", event.startDate.map { KlangradarDateTime.string($0, format: "d. MMMM") } ?? "–", mint)
                    Spacer()
                    previewField("ORT", event.venues?.name ?? "–", mint, trailing: true)
                }
                if filled.isEmpty {
                    Text("Platz unten eintragen – er erscheint dann hier und in Wallet.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.6))
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(filled, id: \.0) { item in previewField(item.0, item.1, mint) }
                        Spacer(minLength: 0)
                    }
                }
                PerforationLine().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 5])).foregroundStyle(.white.opacity(0.22)).frame(height: 1)
                if hasTicket {
                    Button { showsTicket = true } label: {
                        HStack(spacing: 14) {
                            Group {
                                if let code = ticketCode, let rendered = TicketStore.render(code, scale: 6) {
                                    Image(uiImage: rendered).interpolation(.none).resizable().scaledToFit().padding(6).background(.white)
                                } else if let ticketImage {
                                    Image(uiImage: ticketImage).resizable().scaledToFill()
                                }
                            }
                            .frame(width: 66, height: 66)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ticketCodes.count > 1 ? "\(ticketCodes.count) Tickets öffnen" : "Ticket öffnen").font(.headline).foregroundStyle(.white)
                                Text(ticketStatus).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode").font(.title3).foregroundStyle(.white.opacity(0.45))
                        Text("Füge unten dein Ticket hinzu, dann erscheint hier der Code für den Einlass.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .padding(16)
        }
        .background(ink)
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func previewField(_ label: String, _ value: String, _ tint: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(tint)
            Text(value).font(.headline).foregroundStyle(.white).lineLimit(1)
        }
    }

    private var ticketStatus: String {
        if let detectionNote { return detectionNote }
        if ticketCodes.count > 1 { return "\(ticketCodes.count) Tickets · Codes geprüft" }
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
                // 08.11.2026: ein Knopf, Auswahl Foto oder Datei im Menü.
                Menu { pickerButtons } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "ticket.fill").font(.title3).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(KlangradarTheme.accent, in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ticket hinzufügen").font(.headline).foregroundStyle(.primary)
                            Text("Foto, Screenshot, PDF oder Datei").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(KlangradarTheme.accent)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
                }
            }
            // 08.11.2026: Aktionen als Kacheln statt Liste.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if DataScannerViewController.isSupported {
                    actionTile(ticketCode == nil ? "Code scannen" : "Neu scannen", "qrcode.viewfinder", tint: KlangradarTheme.accent) { showsScanner = true }
                }
                actionTile("Als Text", "character.cursor.ibeam", tint: .indigo) { manualCode = ticketCode?.payload ?? ""; showsCodeEntry = true }
                if ticketImage != nil || ticketCode != nil {
                    Menu { pickerButtons } label: { actionTileLabel("Ersetzen", "arrow.triangle.2.circlepath", tint: .teal) }
                        .buttonStyle(.plain)
                    actionTile("Entfernen", "trash", tint: .red) {
                        TicketStore.remove(for: event.id); TicketStore.saveCodes([], for: event.id); ticketImage = nil; ticketCodes = []; detectionNote = nil
                    }
                }
            }
            if ticketCodes.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(ticketCodes.enumerated()), id: \.offset) { index, _ in
                        Button { openCodeIndex = index; showsTicket = true } label: {
                            rowLabel("Ticket \(index + 1) öffnen", systemImage: "qrcode")
                        }
                        .buttonStyle(.plain)
                        if index < ticketCodes.count - 1 { Divider().padding(.leading, 48) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var seatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Platz")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                labeledSeatField($seat.blockLabel, ConcertSeat.defaultLabels.block, ["Block", "Bereich", "Rang", "Parkett", "Loge", "Balkon", "Galerie"], text: $seat.block)
                labeledSeatField($seat.rowLabel, ConcertSeat.defaultLabels.row, ["Reihe"], text: $seat.row)
                labeledSeatField($seat.seatLabel, ConcertSeat.defaultLabels.seat, ["Platz", "Sitz"], text: $seat.seat)
                labeledSeatField($seat.entranceLabel, ConcertSeat.defaultLabels.entrance, ["Eingang", "Tür", "Aufgang", "Tor", "Portal"], text: $seat.entrance)
                ForEach($seat.extras) { $extra in
                    extraSeatField($extra)
                }
            }
            Menu {
                ForEach(["Etage", "Kategorie", "Loge", "Tisch", "Ebene"], id: \.self) { label in
                    Button(label) { seat.extras.append(.init(label: label, value: "")) }
                }
            } label: {
                Label("Angabe hinzufügen", systemImage: "plus.circle").font(.subheadline.weight(.semibold))
            }
            Text("Erscheint am Konzerttag auf dem Sperrbildschirm und in der Live-Aktivität.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func actionTile(_ title: String, _ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionTileLabel(title, symbol, tint: tint) }
            .buttonStyle(.plain)
    }

    private func actionTileLabel(_ title: String, _ symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13), in: .rect(cornerRadius: 10, style: .continuous))
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint == .red ? .red : .primary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
        .contentShape(.rect(cornerRadius: 14))
    }

    @MainActor
    private func loadStripImage() async {
        guard let url = walletImageURL,
              let response = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: response.0) else { return }
        if let saved = ImageFocus.stored(for: event.id) {
            stripFocus = saved
        } else {
            stripFocus = await ImageFocus.detect(in: image)
        }
        stripImage = image
    }

    private var walletImageURL: URL? {
        event.primaryImageURL ?? event.imageUrls?.first.flatMap(URL.init(string:))
    }

    /// 09.11.2026: Bezeichnung wie auf dem Ticket wählbar („Sitz“, „Tür“, „Rang“).
    private func labeledSeatField(_ label: Binding<String>, _ fallback: String, _ options: [String], text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { label.wrappedValue = option == fallback ? "" : option }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(label.wrappedValue.isEmpty ? fallback : label.wrappedValue)
                    if options.count > 1 { Image(systemName: "chevron.up.chevron.down").imageScale(.small) }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .disabled(options.count < 2)
            TextField("–", text: text).font(.title3.weight(.semibold)).textInputAutocapitalization(.characters)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func extraSeatField(_ extra: Binding<ConcertSeat.SeatExtra>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Angabe", text: extra.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button {
                    seat.extras.removeAll { $0.id == extra.wrappedValue.id }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain).accessibilityLabel("Angabe entfernen")
            }
            TextField("–", text: extra.value).font(.title3.weight(.semibold))
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
    let passes: [PKPass]
}

extension TicketSeatEditor {
    @MainActor
    fileprivate func loadWalletPass() async {
        isLoadingWallet = true
        defer { isLoadingWallet = false }
        walletError = nil
        guard let client = SocialStore.shared.repository?.client else { walletError = "Wallet ist gerade nicht verfügbar."; return }
        var base = [URLQueryItem(name: "slug", value: event.slug),
                    URLQueryItem(name: "entrance", value: seat.entrance), URLQueryItem(name: "block", value: seat.block),
                    URLQueryItem(name: "row", value: seat.row), URLQueryItem(name: "seat", value: seat.seat),
                    URLQueryItem(name: "entrance_label", value: seat.entranceLabel), URLQueryItem(name: "block_label", value: seat.blockLabel),
                    URLQueryItem(name: "row_label", value: seat.rowLabel), URLQueryItem(name: "seat_label", value: seat.seatLabel)]
        base += seat.extras.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { URLQueryItem(name: "extra", value: "\($0.label)|\($0.value)") }
        // 09.11.2026: dasselbe Bild wie in der App mitgeben (der Server erreicht
        // nicht jede Bildquelle direkt).
        if let image = walletImageURL, image.scheme == "https" { base.append(URLQueryItem(name: "image", value: image.absoluteString)) }
        base += [URLQueryItem(name: "focus_x", value: String(format: "%.3f", stripFocus.x)),
                 URLQueryItem(name: "focus_y", value: String(format: "%.3f", stripFocus.y))]
        // 08.11.2026: eine Wallet-Karte pro erkanntem Ticket.
        let variants: [[URLQueryItem]] = ticketCodes.isEmpty ? [base] : ticketCodes.enumerated().map { index, code in
            base + [URLQueryItem(name: "code", value: code.payload), URLQueryItem(name: "format", value: code.format)]
                 + (ticketCodes.count > 1 ? [URLQueryItem(name: "ticket", value: "\(index + 1)"), URLQueryItem(name: "of", value: "\(ticketCodes.count)")] : [])
        }
        do {
            var passes: [PKPass] = []
            for items in variants {
                let data = try await client.edgeFunctionData("wallet-pass", queryItems: items, accessToken: SocialStore.shared.token)
                passes.append(try PKPass(data: data))
            }
            walletPass = WalletPassItem(passes: passes)
        } catch APIError.httpStatus(let status, let message) {
            walletError = status == 503
                ? "Apple Wallet ist auf dem Server noch nicht eingerichtet (Zertifikat fehlt)."
                : "Die Wallet-Karte konnte nicht erstellt werden (\(status)): \(message.prefix(140))"
        } catch {
            walletError = "Die Wallet-Karte konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }
}

/// Offizieller „Zu Apple Wallet hinzufügen“-Knopf.
private struct AddToWalletButton: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
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
    let passes: [PKPass]
    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(passes: passes) ?? UIViewController()
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
    let eventID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    /// 09.11.2026: eigener Platz als Markierung im Plan (je Konzert gespeichert).
    @State private var marker: CGPoint?
    @State private var isPlacing = false

    private var markerKey: String { "seatMarker.\(eventID.uuidString.lowercased())" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !seat.isEmpty || isPlacing {
                    Label(isPlacing ? "Tippe auf deinen Platz im Plan" : seat.summary,
                          systemImage: isPlacing ? "hand.tap" : "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KlangradarTheme.accent.opacity(0.1))
                }
                ScrollView([.horizontal, .vertical]) {
                    CachedAsyncImage(url: url, maxPixel: 2400) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                                .overlay {
                                    GeometryReader { proxy in
                                        ZStack(alignment: .topLeading) {
                                            Color.clear.contentShape(Rectangle())
                                                .onTapGesture { location in
                                                    guard isPlacing else { return }
                                                    let point = CGPoint(x: location.x / proxy.size.width, y: location.y / proxy.size.height)
                                                    marker = point
                                                    UserDefaults.standard.set([Double(point.x), Double(point.y)], forKey: markerKey)
                                                    isPlacing = false
                                                    Haptics.confirm()
                                                }
                                            if let marker {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 30)).symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, KlangradarTheme.accent)
                                                    .shadow(radius: 3)
                                                    .position(x: marker.x * proxy.size.width, y: marker.y * proxy.size.height - 12)
                                                    .accessibilityLabel("Mein Platz")
                                            }
                                        }
                                    }
                                }
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                        }
                    }
                    .frame(width: UIScreen.main.bounds.width * scale * pinch)
                    .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) })
                    .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
                }
            }
            .navigationTitle("Saalplan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { isPlacing = true } label: { Label(marker == nil ? "Platz markieren" : "Markierung versetzen", systemImage: "mappin.and.ellipse") }
                        if marker != nil {
                            Button(role: .destructive) {
                                marker = nil
                                UserDefaults.standard.removeObject(forKey: markerKey)
                            } label: { Label("Markierung entfernen", systemImage: "trash") }
                        }
                    } label: { Image(systemName: "mappin.and.ellipse") }
                    .accessibilityLabel("Platz im Plan markieren")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear {
                if let values = UserDefaults.standard.array(forKey: markerKey) as? [Double], values.count == 2 {
                    marker = CGPoint(x: values[0], y: values[1])
                }
            }
        }
    }
}
