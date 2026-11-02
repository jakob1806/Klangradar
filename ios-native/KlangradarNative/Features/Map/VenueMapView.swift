import MapKit
import SwiftUI

struct VenueMapView: View {
    /// "Alle Städte" nur auf der Karte, ohne die globale Stadt zu ändern.
    @State private var showsAllCities = false
    let repository: any ContentRepository
    let eventRepository: any EventRepository
    @ObservedObject var cityStore: CityStore

    @State private var venues: [VenueLocation] = []
    @State private var selectedVenueID: UUID?
    @State private var selectedVenue: VenueLocation?
    // Nutzerfeedback: mehrere Säle desselben Gebäudes (z.B. Gasteig HP8:
    // Isarphilharmonie, Saal X, Blackbox) haben identische Koordinaten und
    // landeten dadurch als EIN nicht einzeln antippbarer Pin auf der Karte.
    // Statt eines Marker pro Venue: Venues an (praktisch) derselben Stelle
    // werden zu einer Gruppe mit Zahl-Badge zusammengefasst; Antippen öffnet
    // eine Auswahlliste statt direkt die Venue-Vorschau.
    @State private var selectedVenueGroup: [VenueLocation]?
    @State private var showsFilter = false
    @State private var onlyWithEvents = false
    @State private var filterText = ""
    // Tag-Filter: nur Orte mit mindestens einer Veranstaltung am gewählten Tag.
    @State private var dayFilterEnabled = false
    @State private var dayFilterDate = Date()
    @State private var venueIDsOnDay: Set<UUID>?
    // Punkt 14 (Nutzerwunsch 24.10.2026): stufenlos erreichbare Orte.
    @State private var stepFreeOnly = false
    @State private var stepFreeVenueIDs: Set<UUID>?
    @State private var position: MapCameraPosition = .region(Self.munichRegion)
    @State private var locationRequester = LocationRequester()
    @State private var locationError: String?
    // Verhindert, dass ein spaeter geladener Venue-Batch die Kamera erneut
    // verschiebt, nachdem sie schon per Standort/erstem Fit gesetzt wurde --
    // sonst wuerde jedes Neuladen der Venues (z.B. nach Filteraenderung) den
    // Nutzer aus einer manuell gewaehlten Ansicht zurueckreissen.
    @State private var hasAutoFitCamera = false

    private static let munichRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.1374, longitude: 11.5755),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )

    private var filteredVenues: [VenueLocation] {
        venues.filter { venue in
            (!onlyWithEvents || venue.upcomingEventCount > 0)
                && (filterText.isEmpty || venue.name.localizedStandardContains(filterText))
                && (!dayFilterEnabled || venueIDsOnDay?.contains(venue.id) ?? true)
                && (!stepFreeOnly || stepFreeVenueIDs?.contains(venue.id) ?? true)
        }
    }

    private var venueGroups: [[VenueLocation]] {
        groupVenuesByLocation(filteredVenues)
    }

    var body: some View {
        NavigationStack {
            mapContent
                // Auch der Karten-Stapel kennt alle Ziele (02.11.2026).
                .contentNavigationDestinations(events: eventRepository, content: repository)
        }
        .sheet(item: $selectedVenue) { venue in
            VenuePreviewSheet(
                venue: venue,
                repository: repository,
                eventRepository: eventRepository
            )
            .presentationDetents([.fraction(0.68), .large])
            .presentationDragIndicator(.visible)
            // Liquid Glass wie in Apple Karten (ab iOS 26 Standard-Sheet).
            .modifier(VenueSheetBackground())
        }
        .sheet(isPresented: showsVenueGroupSheet) {
            VenueGroupPickerSheet(venues: selectedVenueGroup ?? []) { venue in
                selectedVenueGroup = nil
                selectedVenue = venue
            }
            .presentationDetents([.height(72 + CGFloat((selectedVenueGroup?.count ?? 0)) * 76)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsFilter) { filterSheet }
        .task { await loadVenues() }
        .task(id: dayFilterKey) { await loadDayFilter() }
        .task(id: stepFreeOnly) {
            guard stepFreeOnly, stepFreeVenueIDs == nil, let client = SocialStore.shared.repository?.client else { return }
            let rows: [JSONObject]? = try? await client.get(table: "venues", queryItems: [
                URLQueryItem(name: "select", value: "id"),
                URLQueryItem(name: "accessibility->>step_free", value: "eq.true")
            ])
            stepFreeVenueIDs = Set((rows ?? []).compactMap { $0.string("id").flatMap(UUID.init(uuidString:)) })
        }
        .onChange(of: cityStore.selectedCity) { _, _ in
            hasAutoFitCamera = false
            Task { await loadVenues() }
        }
        .onChange(of: showsAllCities) { _, _ in
            hasAutoFitCamera = false
            Task { await loadVenues() }
        }
        .alert("Standort nicht verfügbar", isPresented: Binding(
            get: { locationError != nil },
            set: { if !$0 { locationError = nil } }
        )) {
            Button("OK", role: .cancel) { locationError = nil }
        } message: {
            Text(locationError ?? "Der Standort konnte nicht bestimmt werden.")
        }
    }

    private var showsVenueGroupSheet: Binding<Bool> {
        Binding(get: { selectedVenueGroup != nil }, set: { if !$0 { selectedVenueGroup = nil } })
    }

    private var mapContent: some View {
        Map(position: $position, selection: $selectedVenueID) {
                UserAnnotation()
                ForEach(venueGroups, id: \.self) { group in
                    if let venue = group.first, group.count == 1 {
                        Marker(venue.name, systemImage: "music.note", coordinate: venue.coordinate)
                            .tint(KlangradarTheme.accent)
                            .tag(venue.id)
                    } else if let first = group.first {
                        Annotation(groupTitle(for: group), coordinate: first.coordinate) {
                            Button {
                                selectedVenueGroup = group.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                            } label: {
                                ZStack {
                                    Circle().fill(KlangradarTheme.accent)
                                    Text("\(group.count)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 34, height: 34)
                                .shadow(radius: 2, y: 1)
                            }
                            .accessibilityLabel("\(group.count) Konzertorte an dieser Adresse")
                        }
                    }
                }
        }
        .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                Button { showsFilter = true } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    // Nutzerfeedback: alle drei Bedienelemente über der Karte
                    // (Filter, Stadt-Chip, Standort) sollen denselben Glas-Stil
                    // zeigen — jetzt einheitlich über LiquidGlassSurface statt
                    // teils .regularMaterial, teils (auf iOS 26) gar keinem
                    // manuellen Hintergrund.
                    .background { LiquidGlassSurface(cornerRadius: 18, isInteractive: true) { Color.clear } }
                // Nutzeranfrage: Venues auf der Karte sollen nach Stadt
                // filterbar sein, seit es mehr als München gibt (siehe
                // CityStore/CitySwitcherView) -- Chip nur zeigen, wenn es
                // überhaupt eine Auswahl zu treffen gibt.
                if cityStore.activeCities.count > 1 {
                    CityCompactMenu(
                        cityStore: cityStore,
                        allCitiesSelection: $showsAllCities,
                        isMapMenu: true
                    )
                        .foregroundStyle(.primary)
                }
                    Spacer()
                Button {
                    Task { await locateUser() }
                } label: {
                    Image(systemName: "location.north.fill")
                        .font(.headline)
                        .foregroundStyle(KlangradarTheme.accent)
                        .rotationEffect(.degrees(45))
                        .frame(width: 46, height: 46)
                }
                    .background { LiquidGlassSurface(cornerRadius: 23, isInteractive: true) { Color.clear } }
                    .contentShape(.circle)
                    .accessibilityLabel("Meinen Standort anzeigen")
                }
                .padding(.horizontal, 16)
                if dayFilterEnabled { dayFilterChip.padding(.horizontal, 16) }
                }
                .padding(.top, 10)
            }
            .navigationTitle("Karte")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: selectedVenueID) { _, id in
                selectedVenue = venues.first { $0.id == id }
            }
    }

    private var dayFilterKey: String {
        dayFilterEnabled ? "\(KlangradarDateTime.calendar.startOfDay(for: dayFilterDate).timeIntervalSince1970)" : "aus"
    }

    @MainActor private func loadDayFilter() async {
        guard dayFilterEnabled else {
            // Filter aus: wieder alle Orte zeigen.
            if venueIDsOnDay != nil { fitCamera(to: venues, animated: true) }
            venueIDsOnDay = nil
            return
        }
        venueIDsOnDay = nil
        let ids = try? await repository.venueIDs(withEventsOn: dayFilterDate)
        guard !Task.isCancelled else { return }
        venueIDsOnDay = ids ?? []
        // Kamera auf die Treffer des gewählten Tags zoomen.
        fitCamera(to: filteredVenues, animated: true)
    }

    /// Aktiver Tag-Filter als Glas-Chip über der Karte; ✕ deaktiviert ihn.
    private var dayFilterChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
            Text(KlangradarDateTime.string(dayFilterDate, format: "EEE, d. MMM"))
            Text(venueIDsOnDay != nil ? "· \(filteredVenues.count) Orte" : "· lädt …")
                .foregroundStyle(.secondary)
            Button {
                Haptics.light()
                withAnimation(.snappy) { dayFilterEnabled = false }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Tag-Filter entfernen")
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background { LiquidGlassSurface(cornerRadius: 18, isInteractive: true) { Color.clear } }
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
    }

    @MainActor private func loadVenues() async {
        await cityStore.waitUntilResolved()
        venues = (try? await repository.venueLocations(cityID: showsAllCities ? nil : cityStore.selectedCity?.id)) ?? []
        fitCameraToVenuesIfNeeded()
    }

    @MainActor private func locateUser() async {
        do {
            let coordinate = try await locationRequester.requestOnce()
            hasAutoFitCamera = true
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
                ))
            }
        } catch {
            locationError = error.localizedDescription
        }
    }

    /// Zentriert die Karte einmalig auf alle geladenen Venues, statt fix auf
    /// München stehenzubleiben -- sonst wären Venues in anderen Städten
    /// (Berlin/Hamburg/Frankfurt/Wien, siehe Stadt-Erweiterung) unsichtbar,
    /// bis man manuell dorthin scrollt/zoomt. Läuft nur, solange weder ein
    /// Standort-Fix noch ein vorheriger Auto-Fit die Kamera schon gesetzt hat.
    @MainActor private func fitCameraToVenuesIfNeeded() {
        guard !hasAutoFitCamera, !venues.isEmpty else { return }
        hasAutoFitCamera = true
        fitCamera(to: venues)
    }

    @MainActor private func fitCamera(to targets: [VenueLocation], animated: Bool = false) {
        guard !targets.isEmpty else { return }
        let lats = targets.map(\.coordinate.latitude)
        let lons = targets.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
        )
        let region = MKCoordinateRegion(center: center, span: span)
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }

    private func groupTitle(for group: [VenueLocation]) -> String {
        titleForVenueGroup(group)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Nur Orte mit kommenden Konzerten", isOn: $onlyWithEvents)
                    TextField("Konzertort suchen", text: $filterText)
                }
                Section {
                    Toggle(isOn: $stepFreeOnly) {
                        Label("Stufenlos erreichbar", systemImage: "figure.roll")
                    }
                } footer: {
                    Text("Zeigt Orte, die laut Angaben der Häuser stufenlos zugänglich sind. Details stehen auf der Seite des Konzertorts.")
                }
                Section {
                    Toggle("Nach Tag filtern", isOn: $dayFilterEnabled.animation(.snappy))
                    if dayFilterEnabled {
                        DatePicker(
                            "Tag",
                            selection: $dayFilterDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                        .tint(KlangradarTheme.accent)
                    }
                } header: {
                    Text("Tag")
                } footer: {
                    Text(dayFilterEnabled
                        ? "Die Karte zeigt nur Orte mit einer Veranstaltung am gewählten Tag."
                        : "Wähle einen Tag, um nur Orte mit einer Veranstaltung an diesem Tag zu sehen.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Kartenfilter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Generated by Claude Code — sehr dezenter Tick beim
                    // Bestätigen der Filter, nicht bei jedem einzelnen
                    // Toggle/Chip.
                    Button("Fertig") { Haptics.light(); showsFilter = false }
                }
            }
        }
        // Liquid Glass: ab iOS 26 zeigt das Sheet automatisch Glas; davor
        // dünnes Material statt opakem Formular-Grau.
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
        .presentationDragIndicator(.visible)
    }
}

private struct VenuePreviewSheet: View {
    let venue: VenueLocation
    let repository: any ContentRepository
    let eventRepository: any EventRepository
    @State private var events: [ConcertEvent] = []
    @State private var venueImageURL: URL?
    @State private var websiteURL: URL?
    @State private var phoneURL: URL?
    @State private var galleryURLs: [URL] = []
    @State private var travelMinutes: Int?
    @State private var distanceText: String?
    @Environment(\.dismiss) private var dismiss
    // War auf [ConcertEvent] eingeschränkt — dadurch konnten Venue-/
    // Mitwirkenden-Links von einer hier gepushten EventDetailView nicht
    // wertbasiert weiternavigieren (siehe EntityRoute-Destination unten),
    // sondern blieben auf der alten destination-closure-NavigationLink
    // angewiesen, deren Mischung mit wertbasierten Links im selben Stack zu
    // hängenden/falschen Pushes führte (Nutzerfeedback: "lande wieder auf
    // der Landingpage der Venue, erst 'Zurück' zeigt die gewünschte Seite").
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // Neu gestaltet 01.11.2026 (Nutzerfeedback: Sheet wirkte
            // chaotisch, die Karte schien grünlich durch): fester Hintergrund,
            // Titel auf dem Bild, Konzerte als Karte mit Datumsspalte.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 02.11.2026 (Nutzer, mit Apple-Karten-Screenshot): Kopf wie
                    // in Karten – Name mittig, Teilen links, Schließen rechts;
                    // drei gleich breite Aktionen; Foto darunter.
                    HStack(alignment: .center, spacing: 12) {
                        if let shareURL = venueShareURL {
                            ShareLink(item: shareURL) { circleIcon("square.and.arrow.up") }
                                .accessibilityLabel("Teilen")
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                        VStack(spacing: 2) {
                            Text(venue.name)
                                .font(.title3.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(subtitleLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        Button { dismiss() } label: { circleIcon("xmark") }
                            .accessibilityLabel("Schließen")
                    }

                    // 02.11.2026 (Vergleich mit Apple Karten): schmale, gleich
                    // breite Aktionen, die Route zeigt die Fahrzeit.
                    HStack(spacing: 8) {
                        Button { openRoute() } label: {
                            MapsActionLabel(title: travelMinutes.map { "\($0) Min." } ?? "Route",
                                            systemImage: travelMinutes == nil ? "arrow.triangle.turn.up.right.diamond.fill" : "tram.fill",
                                            prominent: true)
                        }
                        .buttonStyle(.plain)
                        if let slug = venue.slug {
                            Button {
                                navigationPath.append(EntityRoute(kind: .venue, identifier: slug))
                            } label: {
                                MapsActionLabel(title: "Konzerte", systemImage: "music.note.list", prominent: false)
                            }
                            .buttonStyle(.plain)
                        }
                        if let websiteURL {
                            Link(destination: websiteURL) {
                                MapsActionLabel(title: "Website", systemImage: "safari.fill", prominent: false)
                            }
                        }
                        if let phoneURL {
                            Link(destination: phoneURL) {
                                MapsActionLabel(title: "Anrufen", systemImage: "phone.fill", prominent: false)
                            }
                        }
                    }

                    // Kennzahlen wie „Bewertungen · Entfernung“ in Karten.
                    HStack(spacing: 0) {
                        if venue.upcomingEventCount > 0 {
                            mapsStat("Konzerte", "\(venue.upcomingEventCount)", symbol: "music.note")
                        }
                        if let next = events.first?.startDate {
                            mapsStat("Als Nächstes", KlangradarDateTime.string(next, format: "EE, d. MMM"), symbol: "calendar")
                        }
                        if let distanceText {
                            mapsStat("Entfernung", distanceText, symbol: "location")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Ein einzelnes Bild über die volle Breite, unverzerrt
                    // (füllt und wird beschnitten); mehrere als Galerie.
                    if galleryURLs.count == 1, let url = galleryURLs.first {
                        Color.secondary.opacity(0.15)
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .overlay {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: { Color.clear }
                            }
                            .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    } else if !galleryURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(galleryURLs, id: \.self) { url in
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.secondary.opacity(0.15)
                                    }
                                    .frame(width: 220, height: 150)
                                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }

                    if !events.isEmpty {
                        Text("Als Nächstes").font(.headline).padding(.top, 2)
                        VStack(spacing: 0) {
                            ForEach(Array(events.prefix(5).enumerated()), id: \.element.id) { index, event in
                                Button {
                                    navigationPath.append(event)
                                } label: {
                                    // Einheitliche Konzertzeile (02.11.2026).
                                    ConcertRow(event: event)
                                }
                                .buttonStyle(.plain)
                                if index < min(events.count, 5) - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                        // Glas statt weißer Fläche, wie die Karten in Apple Karten.
                        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(20)
            }
            // Kein fester Grund: das Sheet zeigt Liquid Glass (02.11.2026).
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: repository) }
            .navigationDestination(for: EntityRoute.self) { EntityDetailView(route: $0, repository: repository) }
        }
        // 02.11.2026 (Nutzer: „Popup lädt sehr lange“): Konzerte, Detail und
        // Fahrzeit laden parallel; jedes Teil erscheint, sobald es da ist,
        // statt erst nach der kompletten Spielstätten-Detailseite.
        .task { events = (try? await repository.venueEvents(venueID: venue.id, limit: 5)) ?? [] }
        .task { await loadTravel() }
        .task {
            guard let slug = venue.slug else { return }
            let detail = try? await repository.detail(kind: .venue, identifier: slug)
            venueImageURL = detail?.gallery.first?.url ?? detail?.primaryImageURL
            websiteURL = detail?.fields.string("website_url").flatMap(URL.init(string:))
            phoneURL = detail?.fields.string("phone")
                .map { $0.filter { "+0123456789".contains($0) } }
                .flatMap { $0.isEmpty ? nil : URL(string: "tel:\($0)") }
            let gallery = (detail?.gallery ?? []).map(\.url)
            galleryURLs = Array((gallery.isEmpty ? [venueImageURL].compactMap { $0 } : gallery).prefix(6))
        }
    }

    /// Entfernung und ÖPNV-Fahrzeit vom aktuellen Standort (nur mit Freigabe).
    private func loadTravel() async {
        let manager = CLLocationManager()
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus),
              let here = manager.location else { return }
        let target = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
        let meters = here.distance(from: target)
        distanceText = meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: venue.coordinate))
        request.transportType = .transit
        if let eta = try? await MKDirections(request: request).calculateETA() {
            travelMinutes = Int((eta.expectedTravelTime / 60).rounded())
        }
    }

    private func mapsStat(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Label(value, systemImage: symbol).font(.subheadline.weight(.semibold)).labelStyle(.titleAndIcon).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var subtitleLine: String {
        [venue.city, venue.upcomingEventCount > 0 ? "\(venue.upcomingEventCount) Konzerte" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var venueShareURL: URL? {
        venue.slug.flatMap { URL(string: "https://klangradar.com/venue/\($0)") }
    }

    private func circleIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .modifier(MapsGlass(shape: Circle(), tint: nil))
    }


    private func openRoute() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: venue.coordinate))
        item.name = venue.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// Auswahlliste für mehrere Venues an derselben Koordinate (siehe
/// VenueMapView.venueGroups) — z.B. Gasteig HP8 mit Isarphilharmonie, Saal X
/// und Blackbox. Antippen einer Zeile öffnet die normale VenuePreviewSheet
/// für genau diesen Saal.
private struct VenueGroupPickerSheet: View {
    let venues: [VenueLocation]
    let onSelect: (VenueLocation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Mehrere Konzertorte hier")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .padding(.bottom, 4)
            List(venues) { venue in
                Button {
                    onSelect(venue)
                } label: {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: venue.imageURL) { phase in
                            if case let .success(image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                ZStack {
                                    Color.secondary.opacity(0.12)
                                    Image(systemName: "building.columns")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(.rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(venue.name).font(.headline).foregroundStyle(.primary)
                            if venue.upcomingEventCount > 0 {
                                Text("\(venue.upcomingEventCount) kommende Veranstaltungen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

/// Aktion wie in Apple Karten: Symbol über Text, gleich breit, abgerundet;
/// die Hauptaktion farbig gefüllt, die übrigen leicht getönt (Liquid Glass
/// ab iOS 26, darunter Material).
private struct MapsActionLabel: View {
    let title: String
    let systemImage: String
    let prominent: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.body.weight(.semibold))
            Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(prominent ? Color.white : KlangradarTheme.accent)
        .frame(maxWidth: .infinity, minHeight: 52)
        .modifier(MapsGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                            tint: prominent ? KlangradarTheme.accent : KlangradarTheme.accent.opacity(0.18)))
        .contentShape(.rect(cornerRadius: 14))
    }
}

private struct MapsGlass<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive(), in: shape)
        } else {
            content.background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.thinMaterial), in: shape)
        }
    }
}

private struct VenueSheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.presentationBackground(.regularMaterial)
        }
    }
}
