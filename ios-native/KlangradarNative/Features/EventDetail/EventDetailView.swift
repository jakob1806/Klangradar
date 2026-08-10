import SwiftUI
import UIKit

struct EventDetailView: View {
    let event: ConcertEvent
    let repository: any EventRepository
    let contentRepository: any ContentRepository

    @State private var detail: JSONObject?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var fullScreenImage: FullScreenImageReference?
    @EnvironmentObject private var favorites: FavoriteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { screen in
            ScrollView {
                VStack(spacing: 0) {
                    detailHero(
                        height: 305 + max(screen.safeAreaInsets.top, 20),
                        topInset: max(screen.safeAreaInsets.top, 20)
                    )

                    LazyVStack(alignment: .leading, spacing: 28) {
                        titleBlock

                        if let detail {
                            genres(detail)
                            essentialFacts(detail)

                            if let description = detail.string("description_de"), !description.isEmpty {
                                section("Zum Konzert") {
                                    Text(description).font(.body).lineSpacing(4)
                                }
                            }

                            otherDates(detail)
                            program(detail)
                            participants(detail)
                            ticketDetails(detail)
                            accessibility(detail)
                            venue(detail)
                            similarEvents(detail)
                            source(detail)
                        } else if isLoading {
                            ProgressView("Details werden geladen …")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else {
                            ContentUnavailableView(
                                "Details nicht verfügbar",
                                systemImage: "exclamationmark.triangle",
                                description: Text(loadError ?? "Für diese Veranstaltung liegen derzeit keine Detaildaten vor.")
                            )
                        }
                    }
                    .padding(KlangradarTheme.pagePadding)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .containerRelativeFrame(.horizontal)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background { KlangradarBackground().ignoresSafeArea() }
        .background { SwipeBackEnabler().allowsHitTesting(false) }
        .edgeSwipeBack { dismiss() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let detail { ticketBar(detail) }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $fullScreenImage) { FullScreenImageViewer(image: $0) }
        .navigationDestination(for: EntityRoute.self) {
            EntityDetailView(route: $0, repository: contentRepository)
        }
        .task {
            do { detail = try await repository.eventDetail(slug: event.slug) }
            catch { loadError = error.localizedDescription }
            isLoading = false
        }
    }

    private func detailHero(height: CGFloat, topInset: CGFloat) -> some View {
        GeometryReader { proxy in
            EventHeroArtwork(event: event)
                .frame(width: proxy.size.width, height: height)
                .clipped()
                .contentShape(.rect)
                .onTapGesture {
                    if let url = event.primaryImageURL {
                        fullScreenImage = FullScreenImageReference(url: url, title: event.title)
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.56), .clear, .black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .top) {
                    HStack(spacing: 10) {
                        heroButton(systemImage: "chevron.left", label: "Zurück") { dismiss() }
                        Spacer()
                        heroButton(
                            systemImage: favorites.ids.contains(event.id) ? "heart.fill" : "heart",
                            label: "Favorit"
                        ) { Task { await favorites.toggle(event.id) } }
                        ShareLink(item: shareText) {
                            heroButtonLabel(systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Teilen")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, topInset + 10)
                    .frame(width: proxy.size.width)
                }
        }
        .frame(height: height)
        .accessibilityHidden(false)
    }

    private func heroButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { heroButtonLabel(systemImage: systemImage) }
            .accessibilityLabel(label)
    }

    private func heroButtonLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.headline)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.22), in: .circle)
            .background(.ultraThinMaterial, in: .circle)
            .foregroundStyle(.white)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title)
                // Nutzerfeedback: Überschrift in der Detailansicht war zu
                // groß — .title statt .largeTitle, bleibt fett/prominent,
                // wirkt aber weniger überdimensioniert bei langen Titeln.
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = event.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
            if let date = event.startDate {
                Label(
                    KlangradarDateTime.string(date, format: "EEEE, d. MMMM yyyy, HH:mm"),
                    systemImage: "calendar"
                )
                .font(.headline)
            }
        }
    }

    @ViewBuilder private func genres(_ value: JSONObject) -> some View {
        let labels = value.objects("event_genres").compactMap { $0.object("genres")?.string("label_de") }
        let category = value.string("category")
        let allLabels = ([category] + labels).compactMap { $0 }.filter { !$0.isEmpty }
        if !allLabels.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(Set(allLabels)).sorted(), id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.thinMaterial, in: .capsule)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func essentialFacts(_ value: JSONObject) -> some View {
        LiquidGlassSurface(cornerRadius: 24) {
            VStack(spacing: 0) {
                if let venue = value.object("venues") {
                    factRow(
                        icon: "mappin.and.ellipse",
                        title: venue.string("name") ?? event.venueName,
                        subtitle: address(venue)
                    )
                }
                if value.object("venues") != nil, value.integer("duration_minutes") != nil { Divider().padding(.leading, 54) }
                if let minutes = value.integer("duration_minutes") {
                    factRow(
                        icon: "clock",
                        title: "\(minutes) Minuten",
                        subtitle: value.bool("has_intermission") == true ? "Mit Pause" : nil
                    )
                }
                if isOperaEvent(value), let language = value.string("performance_language") {
                    Divider().padding(.leading, 54)
                    factRow(icon: "captions.bubble", title: "Sprache", subtitle: language)
                }
                if let audience = value.string("target_audience") {
                    Divider().padding(.leading, 54)
                    factRow(icon: "person.2", title: "Publikum", subtitle: audience)
                }
            }
        }
    }

    private func factRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(KlangradarTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    @ViewBuilder private func otherDates(_ value: JSONObject) -> some View {
        let rows = value.objects("_other_dates")
        if !rows.isEmpty {
            section("Weitere Termine") {
                LiquidGlassSurface(cornerRadius: 22) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if let otherEvent = event(from: row), let date = otherEvent.startDate {
                                NavigationLink(value: otherEvent) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "calendar")
                                            .foregroundStyle(KlangradarTheme.accent)
                                            .frame(width: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(KlangradarDateTime.string(date, format: "EEEE"))
                                                .font(.headline)
                                            Text(KlangradarDateTime.string(date, format: "d. MMMM yyyy"))
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(KlangradarDateTime.string(date, format: "HH:mm"))
                                            .font(.headline.monospacedDigit())
                                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                    }
                                    .padding(16)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                if index < rows.count - 1 { Divider().padding(.leading, 58) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func program(_ value: JSONObject) -> some View {
        let works = value.objects("event_works").sorted { ($0.integer("position") ?? 0) < ($1.integer("position") ?? 0) }
        let notes = value.string("program_notes_de")
        if !works.isEmpty || notes != nil {
            section("Programm") {
                if !works.isEmpty {
                    LiquidGlassSurface(cornerRadius: 24) {
                        VStack(spacing: 0) {
                            ForEach(Array(works.enumerated()), id: \.offset) { index, link in
                                programRow(link)
                                if index < works.count - 1 { Divider().padding(.leading, 18) }
                            }
                        }
                    }
                }
                if let notes, !notes.isEmpty {
                    Text(notes).font(.body).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
        } else {
            section("Programm") {
                VStack(spacing: 14) {
                    if value.string("program_extraction_status") == "not_published" {
                        ContentUnavailableView(
                            "Programm noch nicht veröffentlicht",
                            systemImage: "music.note.list",
                            description: Text("Der Veranstalter nennt derzeit noch keine konkreten Einzelwerke. Klangradar prüft die Quelle regelmäßig erneut.")
                        )
                    } else {
                        ContentUnavailableView(
                            "Programm wird geprüft",
                            systemImage: "music.note.list",
                            description: Text("Die offizielle Quelle wird gerade auf konkrete Einzelwerke geprüft.")
                        )
                    }
                    if let rawURL = value.string("website_url") ?? value.string("ticket_url"),
                       let url = URL(string: rawURL) {
                        Link(destination: url) {
                            Label("Offizielles Programm öffnen", systemImage: "arrow.up.right.square")
                        }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial, in: .rect(cornerRadius: 22))
            }
        }
    }

    @ViewBuilder private func programRow(_ link: JSONObject) -> some View {
        if let work = link.object("works") {
            VStack(alignment: .leading, spacing: 7) {
                if link.bool("after_intermission") == true {
                    Label("Nach der Pause", systemImage: "pause.fill")
                        .font(.caption.bold())
                        .textCase(.uppercase)
                        .foregroundStyle(KlangradarTheme.accent)
                }
                if let composer = work.object("composer"), let name = composer.string("full_name") {
                    if let route = entityRoute(from: composer, kind: .person) {
                        NavigationLink(value: route) {
                            HStack(spacing: 5) {
                                Text(name)
                                Image(systemName: "chevron.right").font(.caption2.bold())
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KlangradarTheme.accent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KlangradarTheme.accent)
                    }
                }
                Text((work.string("title") ?? "Werk ohne Titel").cleanedWorkTitle)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                let details = [work.string("catalog_number"), work.string("key_signature")].compactMap { $0 }.filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                }

                let movements = work.strings("movements")
                if !movements.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(movements.enumerated()), id: \.offset) { index, movement in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text("\(index + 1).")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(movement).font(.subheadline)
                            }
                        }
                    }
                    .padding(.top, 3)
                }

                if let instrumentation = work.string("instrumentation"), !instrumentation.isEmpty {
                    Label {
                        Text(instrumentation).font(.caption).foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                    .padding(.top, 3)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func participants(_ value: JSONObject) -> some View {
        let rows = value.objects("event_participants")
        if !rows.isEmpty {
            section("Mitwirkende") {
                LiquidGlassSurface(cornerRadius: 22) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if let participant = participantEntity(row), let route = entityRoute(from: participant.value, kind: participant.kind) {
                                NavigationLink(value: route) {
                                    participantLabel(row, participant: participant)
                                }
                                .buttonStyle(.plain)
                            } else if let participant = participantEntity(row) {
                                participantLabel(row, participant: participant)
                            }
                            if index < rows.count - 1 { Divider().padding(.leading, 56) }
                        }
                    }
                }
            }
        }
    }

    private func participantLabel(
        _ row: JSONObject,
        participant: (kind: EntityKind, value: JSONObject)
    ) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: participant.value.string("photo_url").flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Text(initials(participantName(row)))
                            .font(.caption.bold())
                            .foregroundStyle(KlangradarTheme.accent)
                    }
            }
            .frame(width: 44, height: 44)
            .clipShape(.circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(participantName(row)).font(.headline)
                Text(participantRole(row)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(.rect)
    }

    @ViewBuilder private func ticketDetails(_ value: JSONObject) -> some View {
        let details = [value.string("doors_info"), value.string("discount_info"), value.string("presale_fee_info"), value.string("age_restriction")]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if !details.isEmpty {
            section("Ticketinformationen") {
                LiquidGlassSurface(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(details, id: \.self) { Label($0, systemImage: "info.circle") }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func accessibility(_ value: JSONObject) -> some View {
        if let access = value.object("accessibility") {
            let labels = [
                ("wheelchair", "Rollstuhlgerecht", "figure.roll"),
                ("hearing_loop", "Induktive Höranlage", "ear.badge.waveform"),
                ("sign_language", "Gebärdensprache", "hands.and.sparkles")
            ].filter { access.bool($0.0) == true }
            if !labels.isEmpty {
                section("Barrierefreiheit") {
                    ViewThatFits {
                        HStack { ForEach(labels, id: \.0) { Label($0.1, systemImage: $0.2) } }
                        VStack(alignment: .leading, spacing: 10) { ForEach(labels, id: \.0) { Label($0.1, systemImage: $0.2) } }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder private func venue(_ value: JSONObject) -> some View {
        if let venue = value.object("venues") {
            section("Veranstaltungsort") {
                if let route = entityRoute(from: venue, kind: .venue) {
                    NavigationLink(value: route) {
                        venueLabel(venue)
                    }
                    .buttonStyle(.plain)
                } else {
                    venueLabel(venue)
                }
            }
        }
    }

    private func venueLabel(_ venue: JSONObject) -> some View {
        LiquidGlassSurface(cornerRadius: 24) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: venue.string("photo_url").flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12).overlay { Image(systemName: "building.columns") }
                }
                .frame(width: 82, height: 82)
                .clipShape(.rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 5) {
                    Text(venue.string("name") ?? event.venueName).font(.headline)
                    let venueAddress = address(venue)
                    if !venueAddress.isEmpty { Text(venueAddress).font(.subheadline).foregroundStyle(.secondary) }
                    if let description = venue.string("description_de") {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(.rect)
        }
    }

    @ViewBuilder private func similarEvents(_ value: JSONObject) -> some View {
        let rows = value.objects("_similar_events")
        let events = rows.compactMap(event(from:))
        if !events.isEmpty {
            section("Ähnliche Veranstaltungen") {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(events) { item in
                            NavigationLink(value: item) {
                                VStack(alignment: .leading, spacing: 8) {
                                    EventArtwork(event: item)
                                        .frame(width: 200, height: 120)
                                        .clipped()
                                        .clipShape(.rect(cornerRadius: 18))
                                    Text(item.title).font(.headline).lineLimit(2)
                                    Text(item.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 200, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder private func source(_ value: JSONObject) -> some View {
        if value.string("attribution_notice") != nil || value.string("last_verified_at") != nil {
            VStack(alignment: .leading, spacing: 5) {
                if let notice = value.string("attribution_notice") { Text(notice) }
                if let rawDate = value.string("last_verified_at"), let date = FlexibleDateParser.date(from: rawDate) {
                    Text("Zuletzt geprüft: \(KlangradarDateTime.string(date, format: "dd.MM.yyyy"))")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    private func ticketBar(_ value: JSONObject) -> some View {
        let price = priceText(value)
        let status = ticketStatus(value.string("remaining_tickets_status"))
        return HStack(spacing: 16) {
            if price != nil || status != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let price { Text(price).font(.headline) }
                    if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            ticketButton(value)
        }
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private func ticketButton(_ value: JSONObject) -> some View {
        let rawURL = value.string("ticket_url") ?? value.string("website_url")
        let unavailable = value.string("remaining_tickets_status") == "sold_out"
        if let rawURL, let url = URL(string: rawURL) {
            Link(destination: url) {
                Label(unavailable ? "Zur Veranstaltungsseite" : "Tickets kaufen", systemImage: "ticket")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button("Keine Ticketseite", systemImage: "ticket") {}
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func address(_ venue: JSONObject) -> String {
        [
            venue.string("address_street"),
            [venue.string("address_zip"), venue.string("address_city")].compactMap { $0 }.joined(separator: " ")
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private func participantName(_ row: JSONObject) -> String {
        row.object("persons")?.string("full_name") ?? row.object("ensembles")?.string("name") ?? "Unbekannt"
    }

    private func participantEntity(_ row: JSONObject) -> (kind: EntityKind, value: JSONObject)? {
        if let person = row.object("persons") { return (.person, person) }
        if let ensemble = row.object("ensembles") { return (.ensemble, ensemble) }
        return nil
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func entityRoute(from value: JSONObject, kind: EntityKind) -> EntityRoute? {
        guard let identifier = value.string("slug") ?? value.string("id"), !identifier.isEmpty else { return nil }
        return EntityRoute(kind: kind, identifier: identifier)
    }

    private func isOperaEvent(_ value: JSONObject) -> Bool {
        let labels = [value.string("category")]
            + value.objects("event_genres").flatMap { genre in
                [genre.object("genres")?.string("slug"), genre.object("genres")?.string("label_de")]
            }
        return labels.compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains("oper") }
    }

    private func participantRole(_ row: JSONObject) -> String {
        if let roleLabel = row.string("role_label"), !roleLabel.isEmpty { return roleLabel }
        if row.object("ensembles") != nil { return "Ensemble" }
        switch row.string("role") {
        case "dirigent": return "Dirigent:in"
        case "solist": return "Solist:in"
        case "komponist": return "Komponist:in"
        case "chorleiter": return "Chorleitung"
        case "moderator": return "Moderation"
        case let role?: return role.capitalized
        case nil: return "Mitwirkend"
        }
    }

    private func event(from row: JSONObject) -> ConcertEvent? {
        guard
            let id = row.string("id").flatMap(UUID.init(uuidString:)),
            let slug = row.string("slug"),
            let title = row.string("title"),
            let start = row.string("start_datetime")
        else { return nil }

        let venue = row.object("venues")
        let venueID = venue?.string("id").flatMap(UUID.init(uuidString:))
            ?? row.string("venue_id").flatMap(UUID.init(uuidString:))
        let summary = venueID.map {
            VenueSummary(id: $0, name: venue?.string("name") ?? "Ort folgt", photoUrl: venue?.string("photo_url"))
        }
        return ConcertEvent(
            id: id,
            slug: slug,
            title: title,
            subtitle: row.string("subtitle"),
            startDatetime: start,
            imageUrls: row.strings("image_urls"),
            status: row.string("status"),
            venues: summary
        )
    }

    private func ticketStatus(_ status: String?) -> String? {
        switch status {
        case "available": "Tickets verfügbar"
        case "few_left": "Nur noch wenige Tickets"
        case "sold_out": "Ausverkauft"
        case "box_office_only": "Nur Abendkasse"
        default: nil
        }
    }

    private func priceText(_ value: JSONObject) -> String? {
        if value.bool("is_free") == true { return "Kostenlos" }
        guard let minimum = value.number("price_min") else { return nil }
        let currency = value.string("price_currency") ?? "EUR"
        if let maximum = value.number("price_max"), maximum != minimum {
            return "\(formatPrice(minimum))–\(formatPrice(maximum)) \(currency)"
        }
        return "ab \(formatPrice(minimum)) \(currency)"
    }

    private func formatPrice(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 2)))
    }

    private var shareText: String { "\(event.title) · \(event.dateLine)" }
}

struct EdgeSwipeBackModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .onEnded { value in
                    let beganAtLeftEdge = value.startLocation.x <= 32
                    let movedRight = value.translation.width >= 70
                    let projectedRight = value.predictedEndTranslation.width >= 110
                    let mostlyHorizontal = abs(value.translation.height) < 90

                    if beganAtLeftEdge, movedRight, projectedRight, mostlyHorizontal {
                        action()
                    }
                }
        )
    }
}

extension View {
    func edgeSwipeBack(action: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeBackModifier(action: action))
    }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableGesture()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableGesture()
        }

        func enableGesture() {
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

private struct EventHeroArtwork: View {
    let event: ConcertEvent

    var body: some View {
        AsyncImage(url: event.primaryImageURL) { phase in
            switch phase {
            case let .success(image):
                ZStack {
                    Color.black
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 24)
                        .scaleEffect(1.16)
                        .opacity(0.65)
                    image
                        .resizable()
                        .scaledToFit()
                }
            case .empty:
                placeholder.overlay { ProgressView().tint(.white) }
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [KlangradarTheme.deepInk, KlangradarTheme.accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note.list")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
