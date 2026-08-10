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
                            if !detail.events.isEmpty { linkedEvents(detail.events, kind: detail.kind) }
                            metadata(detail)
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
                if let subtitle = detail.subtitle { Text(subtitle).foregroundStyle(.secondary) }
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
                }
            }

        case .person:
            HStack(alignment: .top, spacing: 18) {
                if let imageURL = detail.gallery.first?.url ?? detail.primaryImageURL {
                    Button { showImage(imageURL, title: detail.title) } label: {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
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
                    if let subtitle = detail.subtitle { Text(subtitle).foregroundStyle(.secondary) }
                }
            }

        case .venue:
            EmptyView() // venueHeader(_:) wird stattdessen direkt aufgerufen.
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

    @ViewBuilder private func metadata(_ detail: EntityDetail) -> some View {
        let rows = metadataRows(detail)
        if !rows.isEmpty || detail.fields.string("website_url") != nil {
            section("Informationen") {
                LiquidGlassSurface(cornerRadius: 20) {
                    VStack(spacing: 12) {
                        ForEach(rows, id: \.0) { label, value in
                            LabeledContent(label, value: value)
                        }
                        if let raw = detail.fields.string("website_url"), let url = URL(string: raw) {
                            Link("Offizielle Website", destination: url).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(18)
                }
            }
        }
    }

    private func metadataRows(_ detail: EntityDetail) -> [(String, String)] {
        let fields = detail.fields
        switch detail.kind {
        case .person:
            return [("Nationalität", fields.string("nationality")), ("Geboren", fields.string("birth_date")?.asGermanDate), ("Gestorben", fields.string("death_date")?.asGermanDate), ("Instrument", fields.string("instrument"))].compactMap { label, value in value.map { (label, $0) } }
        case .ensemble:
            return [("Gegründet", fields.integer("founded_year").map(String.init)), ("Herkunft", fields.string("city") ?? fields.string("country"))].compactMap { label, value in value.map { (label, $0) } }
        case .venue:
            let address = [fields.string("address_street"), [fields.string("address_zip"), fields.string("address_city")].compactMap { $0 }.joined(separator: " ")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return [("Adresse", address.isEmpty ? nil : address), ("Telefon", fields.string("phone")), ("ÖPNV", fields.string("public_transport"))].compactMap { label, value in value.map { (label, $0) } }
        case .work:
            return [("Komponist:in", fields.object("composer")?.string("full_name")), ("Komposition", fields.integer("composition_year").map(String.init)), ("Dauer", fields.integer("duration_minutes").map { "\($0) Minuten" }), ("Werkverzeichnis", fields.string("catalog_number")), ("Tonart", fields.string("key_signature")), ("Gattung", fields.string("genre")), ("Besetzung", fields.string("instrumentation")), ("Sätze", fields.strings("movements").isEmpty ? nil : fields.strings("movements").joined(separator: " · "))].compactMap { label, value in value.map { (label, $0) } }
        }
    }

    private func gallery(_ images: [GalleryImage]) -> some View {
        section("Bilder") {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(images) { item in
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
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func linkedEvents(_ events: [LinkedEvent], kind: EntityKind) -> some View {
        let sorted = events
            .filter { kind != .venue || ($0.startDate ?? .distantPast) >= KlangradarDateTime.calendar.startOfDay(for: .now) }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        if !sorted.isEmpty {
            section(kind == .venue ? "Kommende Veranstaltungen" : "Veranstaltungen") {
                if kind == .venue {
                    venueEventGroups(Array(sorted.prefix(6)))
                    if sorted.count > 6 {
                        DisclosureGroup("Weitere \(sorted.count - 6) Konzerte anzeigen") {
                            venueEventGroups(Array(sorted.dropFirst(6)))
                                .padding(.top, 12)
                        }
                        .font(.headline)
                        .tint(KlangradarTheme.accent)
                        .padding(.top, 4)
                    }
                } else {
                    LiquidGlassSurface(cornerRadius: 22) {
                        VStack(spacing: 0) {
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, event in
                                linkedEventRow(event, showsVenue: true)
                                if index < sorted.count - 1 { Divider().padding(.leading, 78) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func venueEventGroups(_ events: [LinkedEvent]) -> some View {
        let groups = monthGroups(events)
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 9) {
                    Text(KlangradarDateTime.string(group.month, format: "MMMM yyyy"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LiquidGlassSurface(cornerRadius: 22) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                linkedEventRow(event, showsVenue: false)
                                if index < group.events.count - 1 { Divider().padding(.leading, 78) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func linkedEventRow(_ event: LinkedEvent, showsVenue: Bool) -> some View {
        if let concert = event.concertEvent {
            NavigationLink(value: concert) { linkedEventLabel(event, showsVenue: showsVenue) }
                .buttonStyle(.plain)
        } else {
            linkedEventLabel(event, showsVenue: showsVenue)
        }
    }

    private func linkedEventLabel(_ event: LinkedEvent, showsVenue: Bool) -> some View {
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
        .padding(14)
        .contentShape(.rect)
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
