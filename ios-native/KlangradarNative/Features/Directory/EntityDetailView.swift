import MapKit
import SwiftUI

struct EntityRoute: Hashable {
    let kind: EntityKind
    let identifier: String
}

struct EntityDetailView: View {
    let route: EntityRoute
    let repository: any ContentRepository
    @State private var detail: EntityDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var fullScreenImage: FullScreenImageReference?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var follows: FollowStore

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if detail.kind == .venue {
                            venueHeader(detail)
                            followButton(detail)
                            venueLocationMap(detail)
                            if !detail.events.isEmpty { linkedEvents(detail.events, kind: detail.kind) }
                            metadata(detail)
                            venueGuide(detail)
                            if let biography = biography(in: detail) {
                                section("Über \(detail.title)") { Text(biography).lineSpacing(4) }
                            }
                            if !detail.gallery.isEmpty { gallery(detail.gallery) }
                        } else {
                            header(detail)
                            followButton(detail)
                            metadata(detail)
                            if let biography = biography(in: detail) {
                                section("Über \(detail.title)") { Text(biography).lineSpacing(4) }
                            }
                            if detail.kind != .work, !detail.gallery.isEmpty { gallery(detail.gallery) }
                            if !detail.events.isEmpty { linkedEvents(detail.events, kind: detail.kind) }
                        }
                        if !detail.similar.isEmpty {
                            similar(detail.similar, kind: detail.kind)
                        }
                        if detail.kind != .work {
                            ReportContentLink(entityType: detail.kind.rawValue, entityID: detail.id)
                        }
                    }
                    .padding(KlangradarTheme.pagePadding)
                    .padding(.bottom, 100)
                }
                .navigationTitle(detail.kind == .work ? detail.title.cleanedWorkTitle : detail.title)
                .navigationBarTitleDisplayMode(.inline)
            } else if isLoading {
                ProgressView("Inhalt wird geladen …")
            } else {
                ContentUnavailableView("Eintrag nicht verfügbar", systemImage: "exclamationmark.circle", description: Text(errorMessage ?? "Der Eintrag wurde nicht gefunden."))
            }
        }
        .edgeSwipeBack { dismiss() }
        .fullScreenCover(item: $fullScreenImage) { FullScreenImageViewer(image: $0) }
        .task { await load() }
    }

    @ViewBuilder private func header(_ detail: EntityDetail) -> some View {
        switch detail.kind {
        case .work:
            VStack(alignment: .leading, spacing: 8) {
                Text("WERK").font(.caption.bold()).tracking(1).foregroundStyle(KlangradarTheme.accent)
                Text(detail.title.cleanedWorkTitle).font(.largeTitle.bold())
                if let subtitle = detail.subtitle { Text(subtitle.leadingUppercased).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .ensemble:
            VStack(alignment: .leading, spacing: 14) {
                if let imageURL = detail.gallery.first?.url ?? detail.primaryImageURL {
                    Button {
                        showImage(imageURL, title: detail.title)
                    } label: {
                        constrainedEntityImage(
                            url: imageURL,
                            height: 190,
                            systemImage: detail.kind.systemImage
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bild von \(detail.title) vergrößern")
                } else {
                    entityImagePlaceholder(height: 190, systemImage: detail.kind.systemImage)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(detail.kind.title.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                    Text(detail.title).font(.title.bold())
                    parentEnsembleLink(detail.fields.object("parent"))
                    childEnsembleLinks(detail.fields.objects("children"))
                }
            }

        case .person:
            HStack(alignment: .top, spacing: 18) {
                if let imageURL = detail.primaryImageURL ?? detail.gallery.first?.url {
                    Button { showImage(imageURL, title: detail.title) } label: {
                        CroppedAsyncImage(url: imageURL, crop: detail.avatarCrop) {
                            Circle().fill(.quaternary)
                                .overlay { Image(systemName: detail.kind.systemImage).font(.largeTitle) }
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bild von \(detail.title) vergrößern")
                } else {
                    Circle().fill(.quaternary)
                        .overlay { Image(systemName: detail.kind.systemImage).font(.largeTitle) }
                        .frame(width: 120, height: 120)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.kind.title.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
                    Text(detail.title).font(.title.bold())
                    if let subtitle = detail.subtitle { Text(subtitle.leadingUppercased).foregroundStyle(.secondary) }
                    parentEnsembleLink(detail.fields.object("member_of"))
                }
            }

        case .venue:
            EmptyView() // venueHeader(_:) wird stattdessen direkt aufgerufen.
        }
    }

    @ViewBuilder private func childEnsembleLinks(_ rows: [JSONObject]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("ZUGEHÖRIGE ENSEMBLES")
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            if let slug = row.string("slug"), let name = row.string("name") {
                                NavigationLink(value: EntityRoute(kind: .ensemble, identifier: slug)) {
                                    Text(name)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(.thinMaterial, in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Nutzeranfrage: Zugehörigkeit zu einem übergeordneten Ensemble sichtbar
    /// machen, z.B. "Solist des Tölzer Knabenchors" → "Tölzer Knabenchor"
    /// oder "Kammerorchester des BR" → "Symphonieorchester des BR". `row`
    /// kommt direkt aus dem "member_of"/"parent"-Join in ContentRepository.detail.
    @ViewBuilder private func parentEnsembleLink(_ row: JSONObject?) -> some View {
        if let row, let slug = row.string("slug"), let name = row.string("name") {
            NavigationLink(value: EntityRoute(kind: .ensemble, identifier: slug)) {
                HStack(spacing: 4) {
                    Text("Teil von \(name)")
                    Image(systemName: "chevron.right").font(.caption2.bold())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KlangradarTheme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// Nutzerwunsch: "bestimmten Ensembles/Personen/Venues folgen" — Button
    /// direkt auf der Detailseite, nutzt denselben Zustand wie Profil →
    /// Interessen (siehe FollowStore). Keine eigene Version für Werke, die
    /// haben keine Interessen-Kategorie.
    @ViewBuilder private func followButton(_ detail: EntityDetail) -> some View {
        if detail.kind != .work, follows.isSignedIn, let id = UUID(uuidString: detail.id) {
            let following = follows.isFollowing(kind: detail.kind, id: id)
            Button {
                Task { await follows.toggle(kind: detail.kind, id: id) }
            } label: {
                Label(following ? "Gefolgt" : "Folgen", systemImage: following ? "checkmark" : "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .background(following ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(KlangradarTheme.accent), in: .capsule)
            .foregroundStyle(following ? Color.primary : Color.white)
            .accessibilityLabel(following ? "\(detail.title) wird gefolgt, zum Entfolgen antippen" : "\(detail.title) folgen")
        }
    }

    private func venueHeader(_ detail: EntityDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let imageURL = detail.gallery.first?.url ?? detail.primaryImageURL {
                Button { showImage(imageURL, title: detail.title) } label: {
                    constrainedEntityImage(url: imageURL, height: 210, systemImage: "building.columns")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bild von \(detail.title) vergrößern")
            } else {
                entityImagePlaceholder(height: 210, systemImage: "building.columns")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("KONZERTORT").font(.caption.bold()).tracking(1).foregroundStyle(KlangradarTheme.accent)
                Text(detail.title).font(.largeTitle.bold())
                if let city = detail.fields.string("address_city") { Text(city).font(.title3).foregroundStyle(.secondary) }
            }
        }
    }

    /// Nutzerwunsch: zwischen "Folgen" und "Kommende Veranstaltungen" soll
    /// eine bewegliche Karte zeigen, wo der Konzertort ungefähr liegt — im
    /// selben Format wie das Titelbild oben. `Map` (MapKit/SwiftUI) ist per
    /// Default pan-/zoombar, kein zusätzliches Gesture-Handling nötig.
    @ViewBuilder private func venueLocationMap(_ detail: EntityDetail) -> some View {
        if let lat = detail.venueLatitude, let lng = detail.venueLongitude {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            Map(initialPosition: .region(
                MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012))
            )) {
                Marker(detail.title, coordinate: coordinate)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipShape(.rect(cornerRadius: 22))
            .accessibilityLabel("Karte: Lage von \(detail.title)")
        }
    }

    @ViewBuilder private func metadata(_ detail: EntityDetail) -> some View {
        let rows = metadataRows(detail)
        let socialLinks = detail.fields.object("social_links") ?? [:]
        let musicPlatforms = socialLinks.keys.filter { ["spotify", "apple_music"].contains($0.lowercased()) && socialLinks.string($0)?.isEmpty == false }.sorted()
        let socialPlatforms = socialLinks.keys.filter { !["spotify", "apple_music"].contains($0.lowercased()) && socialLinks.string($0)?.isEmpty == false }.sorted()

        section("Kontakt") {
            LiquidGlassSurface(cornerRadius: 20) {
                VStack(spacing: 12) {
                    ForEach(rows, id: \.0) { label, value in
                        LabeledContent(label, value: value)
                    }
                    if let raw = detail.fields.string("website_url"), let url = URL(string: raw) {
                        Link("Offizielle Website", destination: url).frame(maxWidth: .infinity, alignment: .leading)
                    } else if rows.isEmpty {
                        Text("Noch keine Kontaktdaten hinterlegt.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(18)
            }
        }

        if !socialPlatforms.isEmpty {
            section("Social Media") {
                LiquidGlassSurface(cornerRadius: 20) {
                    VStack(spacing: 12) {
                        ForEach(socialPlatforms, id: \.self) { platform in
                            platformLink(platform, links: socialLinks)
                        }
                    }.padding(18)
                }
            }
        }

        if !musicPlatforms.isEmpty {
            section("Musik") {
                LiquidGlassSurface(cornerRadius: 20) {
                    VStack(spacing: 12) {
                        ForEach(musicPlatforms, id: \.self) { platform in
                            platformLink(platform, links: socialLinks)
                        }
                    }.padding(18)
                }
            }
        }
    }

    @ViewBuilder private func platformLink(_ platform: String, links: JSONObject) -> some View {
        if let raw = links.string(platform), let url = URL(string: raw) {
            Link(destination: url) {
                HStack(spacing: 12) {
                    SocialPlatformIcon(platform: platform)
                    Text(socialLabel(platform)).font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func venueGuide(_ detail: EntityDetail) -> some View {
        let fields = detail.fields
        let rows: [(String, String, String)] = [
            ("Anreise & ÖPNV", "tram.fill", [fields.string("mvv_stops"), fields.string("arrival_info_de")].compactMap { $0 }.joined(separator: "\n\n")),
            ("Parken", "parkingsign.circle.fill", fields.string("parking_info_de") ?? ""),
            ("Barrierefreiheit", "figure.roll", accessibilitySummary(fields.object("accessibility"))),
            ("Einlass & Garderobe", "door.left.hand.open", fields.string("doors_info_de") ?? ""),
            ("Gastronomie", "fork.knife", fields.string("catering_info_de") ?? "")
        ].filter { !$0.2.isEmpty }
        if !rows.isEmpty {
            section("Dein Besuch") {
                VStack(spacing: 10) {
                    ForEach(rows, id: \.0) { title, icon, text in
                        LiquidGlassSurface(cornerRadius: 18) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon).foregroundStyle(KlangradarTheme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(text).font(.subheadline).foregroundStyle(.secondary) }
                                Spacer(minLength: 0)
                            }.padding(16)
                        }
                    }
                }
            }
        }
    }

    private func accessibilitySummary(_ value: JSONObject?) -> String {
        guard let value else { return "" }
        return value.keys.sorted().compactMap { key in
            if let text = value.string(key), !text.isEmpty { return "\(key.replacingOccurrences(of: "_", with: " ").capitalized): \(text)" }
            if let flag = value.bool(key), flag { return key.replacingOccurrences(of: "_", with: " ").capitalized }
            return nil
        }.joined(separator: "\n")
    }

    private func socialLabel(_ platform: String) -> String {
        switch platform.lowercased() {
        case "instagram": return "Instagram"
        case "facebook": return "Facebook"
        case "youtube": return "YouTube"
        case "spotify": return "Spotify"
        case "apple_music": return "Apple Music"
        case "tiktok": return "TikTok"
        case "linkedin": return "LinkedIn"
        default: return platform.prefix(1).uppercased() + platform.dropFirst()
        }
    }

}

/// Eigenständige, farbige Plattform-Badges statt generischer Link-Symbole.
/// Die Elemente bleiben bewusst ohne externe Bild-Downloads zuverlässig
/// offline sichtbar und geben jeder Plattform sofort ihre übliche Identität.
private struct SocialPlatformIcon: View {
    let platform: String

    var body: some View {
        Group {
            switch platform.lowercased() {
            case "instagram":
                Image(systemName: "camera.fill")
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .padding(-7)
                    )
            case "facebook":
                Text("f").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .background(Color(red: 0.05, green: 0.40, blue: 1).padding(-8))
            case "youtube":
                Image(systemName: "play.fill").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .background(Color.red.padding(.horizontal, -8).padding(.vertical, -6))
            case "spotify":
                Image(systemName: "wave.3.right.circle.fill").font(.title3).foregroundStyle(.black)
                    .background(Color(red: 0.12, green: 0.84, blue: 0.38).padding(-5))
            case "apple_music":
                Image(systemName: "music.note").font(.body.weight(.bold)).foregroundStyle(.white)
                    .background(Color.pink.padding(-7))
            case "tiktok":
                Image(systemName: "music.note").font(.body.weight(.bold)).foregroundStyle(.white)
                    .background(Color.black.padding(-7))
            case "linkedin":
                Text("in").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .background(Color(red: 0.04, green: 0.39, blue: 0.68).padding(-7))
            default:
                Image(systemName: "link").foregroundStyle(.white).background(Color.secondary.padding(-7))
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

private extension EntityDetailView {
    func socialSymbol(_ platform: String) -> String {
        switch platform.lowercased() {
        case "instagram": return "camera"
        case "facebook", "linkedin": return "person.2"
        case "youtube": return "play.rectangle"
        case "spotify", "apple_music", "tiktok": return "music.note"
        default: return "link"
        }
    }

    private func metadataRows(_ detail: EntityDetail) -> [(String, String)] {
        let fields = detail.fields
        switch detail.kind {
        case .person:
            return [("Nationalität", fields.string("nationality")), ("Geboren", fields.string("birth_date")?.asGermanDate), ("Gestorben", fields.string("death_date")?.asGermanDate), ("Instrument", formattedInstrument(fields.string("instrument")))].compactMap { label, value in value.map { (label, $0) } }
        case .ensemble:
            return [("Gegründet", fields.integer("founded_year").map(String.init)), ("Herkunft", fields.string("city") ?? fields.string("country"))].compactMap { label, value in value.map { (label, $0) } }
        case .venue:
            let address = [fields.string("address_street"), [fields.string("address_zip"), fields.string("address_city")].compactMap { $0 }.joined(separator: " ")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return [("Adresse", address.isEmpty ? nil : address), ("Telefon", fields.string("phone")), ("E-Mail", fields.string("email"))].compactMap { label, value in value.map { (label, $0) } }
        case .work:
            return [("Komponist:in", fields.object("composer")?.string("full_name")), ("Komposition", fields.integer("composition_year").map(String.init)), ("Dauer", fields.integer("duration_minutes").map { "\($0) Minuten" }), ("Werkverzeichnis", fields.string("catalog_number")), ("Tonart", fields.string("key_signature")), ("Gattung", fields.string("genre")), ("Besetzung", fields.string("instrumentation")), ("Sätze", fields.strings("movements").isEmpty ? nil : fields.strings("movements").joined(separator: " · "))].compactMap { label, value in value.map { (label, $0) } }
        }
    }

    private func formattedInstrument(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("[") && raw.hasSuffix("]"),
           let data = raw.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " · ")
        }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private func gallery(_ images: [GalleryImage]) -> some View {
        section("Bilder") {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(images) { item in
                        VStack(alignment: .trailing, spacing: 0) {
                            Button {
                                showImage(item.url, title: item.altText ?? "Galeriebild")
                            } label: {
                                AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                                    .frame(width: 250, height: 170)
                                    .clipped()
                                    .clipShape(.rect(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Galeriebild vergrößern")

                            // Nur sichtbar, wenn ein Fotograf hinterlegt ist —
                            // Bilder ohne Fotografen, aber mit geprüfter Lizenz
                            // (license_status confirmed_*, siehe ContentRepository.
                            // gallery) sind bereits freigegeben, zeigen also
                            // bewusst keinen "Quelle unbekannt"-Hinweis.
                            if let photographer = item.photographer {
                                photoCredit(photographer, sourceURL: item.sourceURL)
                            }
                        }
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func photoCredit(_ photographer: String, sourceURL: URL?) -> some View {
        let label = Text("© \(photographer)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        if let sourceURL {
            Link(destination: sourceURL) { label }
        } else {
            label
        }
    }

    /// Nutzerwunsch: Konzertlisten auf Venue-/Ensemble-/Personen-Detailseiten
    /// nach Monaten gruppiert, jeder Monat einzeln ein-/ausklappbar. Der
    /// vorherige, nur bei Venues aktive "Weitere X Konzerte anzeigen"-
    /// DisclosureGroup-Button behielt nach dem Ausklappen denselben Text,
    /// obwohl dann bereits alles sichtbar war — MonthGroupedEventList
    /// (unten) ersetzt ihn durch einen Button, der nach dem Ausklappen zu
    /// "Alle einklappen" wechselt.
    @ViewBuilder private func linkedEvents(_ events: [LinkedEvent], kind: EntityKind) -> some View {
        let sorted = events
            .filter { kind != .venue || ($0.startDate ?? .distantPast) >= KlangradarDateTime.calendar.startOfDay(for: .now) }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        if !sorted.isEmpty {
            section(kind == .venue ? "Kommende Veranstaltungen" : "Veranstaltungen") {
                VStack(alignment: .leading, spacing: 12) {
                    if let icsURL = calendarExportURL(sorted, kind: kind) {
                        ShareLink(item: icsURL) {
                            Label("Alle Konzerte exportieren", systemImage: "calendar.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(KlangradarTheme.accent)
                    }
                    MonthGroupedEventList(groups: monthGroups(sorted)) { event in
                        AnyView(linkedEventRow(event, showsVenue: kind != .venue, showsProgram: kind != .venue))
                    }
                }
            }
        }
    }

    /// Nutzerwunsch: Kalender-Export für alle Konzerte einer gefolgten
    /// Person/eines Ensembles/eines Orts in einer Datei (mehrere VEVENT-
    /// Blöcke, System-Kalender bieten dafür einen Sammel-Import an).
    private func calendarExportURL(_ events: [LinkedEvent], kind: EntityKind) -> URL? {
        let inputs = events.compactMap { event -> IcsEventInput? in
            guard let start = event.startDate else { return nil }
            return IcsEventInput(uid: event.id, title: event.title, start: start, location: event.venueName)
        }
        guard !inputs.isEmpty else { return nil }
        return try? IcsExport.write(inputs, fileName: "\(kind.rawValue)_konzerte.ics")
    }

    @ViewBuilder private func linkedEventRow(_ event: LinkedEvent, showsVenue: Bool, showsProgram: Bool) -> some View {
        if let concert = event.concertEvent {
            NavigationLink(value: concert) { linkedEventLabel(event, showsVenue: showsVenue, showsProgram: showsProgram) }
                .buttonStyle(.plain)
        } else {
            linkedEventLabel(event, showsVenue: showsVenue, showsProgram: showsProgram)
        }
    }

    private func linkedEventLabel(_ event: LinkedEvent, showsVenue: Bool, showsProgram: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(event.startDate.map { KlangradarDateTime.string($0, format: "dd") } ?? "–")
                        .font(.title3.bold())
                    Text(event.startDate.map { KlangradarDateTime.string($0, format: "MMM") } ?? "")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(KlangradarTheme.accent)
                }
                .frame(width: 50, height: 54)
                .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title).font(.headline).lineLimit(2)
                    HStack(spacing: 5) {
                        if let date = event.startDate {
                            Text(KlangradarDateTime.string(date, format: "EEE HH:mm"))
                        }
                        if showsVenue, let venue = event.venueName { Text("· \(venue)") }
                        if let role = event.role { Text("· \(role)") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            if showsProgram, !event.programWorks.isEmpty {
                programList(event.programWorks)
            }
        }
        .padding(14)
        .contentShape(.rect)
    }

    /// Nutzerwunsch: Programm unter jedem Konzert soll immer vollständig
    /// sichtbar sein statt auf zwei Zeilen abgeschnitten — deshalb jedes
    /// Werk als eigene Zeile statt einer zusammengefassten, truncated
    /// Text-Zeile. Rückt unter das Datumsfeld (50pt + 14pt Abstand) ein,
    /// damit es optisch zur Konzertzeile gehört statt lose darunter zu stehen.
    private func programList(_ works: [ProgramWorkSummary]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(works.enumerated()), id: \.offset) { _, work in
                Group {
                    if let composer = work.composerName {
                        Text(composer).fontWeight(.semibold) + Text("  \(work.title)")
                    } else {
                        Text(work.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 64)
        .padding(.top, 6)
    }

    private func monthGroups(_ events: [LinkedEvent]) -> [LinkedEventMonthGroup] {
        let calendar = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: events) { event in
            event.startDate.flatMap { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) } ?? .distantFuture
        }
        return grouped.keys.sorted().map { LinkedEventMonthGroup(month: $0, events: grouped[$0] ?? []) }
    }

    @ViewBuilder private func similar(_ items: [DirectoryItem], kind: EntityKind) -> some View {
        section("Ähnliche Einträge") {
            if kind == .person || kind == .ensemble {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(items) { item in
                            NavigationLink(value: EntityRoute(kind: item.kind, identifier: item.slug ?? item.id)) {
                                VStack(spacing: 9) {
                                    CroppedAsyncImage(url: item.imageURL, crop: item.avatarCrop) {
                                        Circle().fill(.quaternary).overlay { Image(systemName: item.kind.systemImage).font(.title2) }
                                    }
                                    .frame(width: 86, height: 86)
                                    .clipShape(.circle)
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(width: 112)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                ForEach(items) { item in
                    NavigationLink(value: EntityRoute(kind: item.kind, identifier: item.slug ?? item.id)) {
                        Label(item.title, systemImage: item.kind.systemImage)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.title2.bold()); content() }
    }

    private func biography(in detail: EntityDetail) -> String? {
        ["biography_de", "description_de", "bio_de", "description"].compactMap { detail.fields.string($0) }.first
    }

    private func showImage(_ url: URL, title: String) {
        fullScreenImage = FullScreenImageReference(url: url, title: title)
    }

    private func constrainedEntityImage(url: URL, height: CGFloat, systemImage: String) -> some View {
        GeometryReader { proxy in
            AsyncImage(url: url) { image in
                ZStack {
                    Color.black
                    image.resizable().scaledToFill().blur(radius: 18).scaleEffect(1.12).opacity(0.5)
                    image.resizable().scaledToFit()
                }
            } placeholder: {
                entityImagePlaceholder(height: height, systemImage: systemImage)
            }
            .frame(width: proxy.size.width, height: height)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 22))
        .contentShape(.rect)
    }

    private func entityImagePlaceholder(height: CGFloat, systemImage: String) -> some View {
        LinearGradient(
            colors: [KlangradarTheme.deepInk, KlangradarTheme.accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay { Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.white.opacity(0.8)) }
        .clipShape(.rect(cornerRadius: 22))
    }

    private func load() async {
        do { detail = try await repository.detail(kind: route.kind, identifier: route.identifier) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct LinkedEventMonthGroup: Identifiable {
    let month: Date
    let events: [LinkedEvent]
    var id: Date { month }
}

/// Monatsweise gruppierte, einzeln ein-/ausklappbare Konzertliste (Nutzer-
/// wunsch, siehe EntityDetailView.linkedEvents). Standardmäßig ist nur der
/// erste Monat sichtbar/ausgeklappt; weitere Monate kommen erst nach Tippen
/// auf den Sammel-Button dazu, dessen Beschriftung danach zu "Alle
/// einklappen" wechselt statt (wie zuvor bei DisclosureGroup) unverändert
/// zu bleiben. Unabhängig davon lässt sich jeder einzelne sichtbare Monat
/// über seine Kopfzeile ein-/ausklappen.
private struct MonthGroupedEventList: View {
    let groups: [LinkedEventMonthGroup]
    let rowContent: (LinkedEvent) -> AnyView

    private static let initiallyVisibleMonths = 1

    @State private var expandedMonths: Set<Date>
    @State private var showingAll: Bool

    init(groups: [LinkedEventMonthGroup], rowContent: @escaping (LinkedEvent) -> AnyView) {
        self.groups = groups
        self.rowContent = rowContent
        _expandedMonths = State(initialValue: Set(groups.prefix(Self.initiallyVisibleMonths).map(\.month)))
        _showingAll = State(initialValue: groups.count <= Self.initiallyVisibleMonths)
    }

    private var visibleGroups: [LinkedEventMonthGroup] {
        showingAll ? groups : Array(groups.prefix(Self.initiallyVisibleMonths))
    }

    private var hiddenEventCount: Int {
        groups.dropFirst(Self.initiallyVisibleMonths).reduce(0) { $0 + $1.events.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(visibleGroups) { group in
                monthSection(group)
            }
            if groups.count > Self.initiallyVisibleMonths {
                Button {
                    withAnimation {
                        if showingAll {
                            showingAll = false
                            expandedMonths = Set(groups.prefix(Self.initiallyVisibleMonths).map(\.month))
                        } else {
                            showingAll = true
                            expandedMonths = Set(groups.map(\.month))
                        }
                    }
                } label: {
                    Text(showingAll ? "Alle einklappen" : "Weitere \(hiddenEventCount) Konzerte anzeigen")
                }
                .font(.headline)
                .tint(KlangradarTheme.accent)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder private func monthSection(_ group: LinkedEventMonthGroup) -> some View {
        let isExpanded = expandedMonths.contains(group.month)
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation {
                    if isExpanded { expandedMonths.remove(group.month) } else { expandedMonths.insert(group.month) }
                }
            } label: {
                HStack {
                    Text(KlangradarDateTime.string(group.month, format: "MMMM yyyy"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(group.events.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                LiquidGlassSurface(cornerRadius: 22) {
                    VStack(spacing: 0) {
                        ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                            rowContent(event)
                            if index < group.events.count - 1 { Divider().padding(.leading, 78) }
                        }
                    }
                }
            }
        }
    }
}
