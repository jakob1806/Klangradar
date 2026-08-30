import MapKit
import SwiftUI

struct VenueMapView: View {
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
        }
    }

    private var venueGroups: [[VenueLocation]] {
        groupVenuesByLocation(filteredVenues)
    }

    var body: some View {
        NavigationStack {
            mapContent
        }
        .sheet(item: $selectedVenue) { venue in
            VenuePreviewSheet(
                venue: venue,
                repository: repository,
                eventRepository: eventRepository
            )
            .presentationDetents([.fraction(0.68), .large])
            .presentationDragIndicator(.visible)
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
        .onChange(of: cityStore.selectedCity) { _, _ in
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
                HStack(spacing: 12) {
                Button { showsFilter = true } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.regularMaterial, in: .capsule)
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                // Nutzeranfrage: Venues auf der Karte sollen nach Stadt
                // filterbar sein, seit es mehr als München gibt (siehe
                // CityStore/CitySwitcherView) -- Chip nur zeigen, wenn es
                // überhaupt eine Auswahl zu treffen gibt.
                if cityStore.activeCities.count > 1 {
                    CityCompactMenu(
                        cityStore: cityStore,
                        allowsAllCities: true,
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
                        .rotationEffect(.degrees(28))
                }
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: .circle)
                    .contentShape(.circle)
                    .accessibilityLabel("Meinen Standort anzeigen")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .navigationTitle("Karte")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: selectedVenueID) { _, id in
                selectedVenue = venues.first { $0.id == id }
            }
    }

    @MainActor private func loadVenues() async {
        venues = (try? await repository.venueLocations(cityID: cityStore.selectedCity?.id)) ?? []
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
        let lats = venues.map(\.coordinate.latitude)
        let lons = venues.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.12),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.12)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func groupTitle(for group: [VenueLocation]) -> String {
        titleForVenueGroup(group)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Toggle("Nur Orte mit kommenden Konzerten", isOn: $onlyWithEvents)
                TextField("Konzertort suchen", text: $filterText)
            }
            .navigationTitle("Kartenfilter")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { showsFilter = false }
                }
            }
        }
        .presentationDetents([.height(230)])
    }
}

private struct VenuePreviewSheet: View {
    let venue: VenueLocation
    let repository: any ContentRepository
    let eventRepository: any EventRepository
    @State private var events: [ConcertEvent] = []
    @State private var venueImageURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AsyncImage(url: venueImageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        LinearGradient(
                            colors: [KlangradarTheme.deepInk, KlangradarTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay { Image(systemName: "building.columns").font(.largeTitle).foregroundStyle(.white.opacity(0.8)) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(venue.name).font(.title2.bold())
                        if let city = venue.city { Text(city).foregroundStyle(.secondary) }
                        Text("\(venue.upcomingEventCount) kommende Veranstaltungen").font(.subheadline).foregroundStyle(.secondary)
                    }

                    if !events.isEmpty { Text("Nächste Konzerte").font(.headline) }
                    ForEach(events.prefix(3)) { event in
                        NavigationLink(value: event) {
                            HStack(spacing: 12) {
                                EventArtwork(event: event).frame(width: 48, height: 48).clipped().clipShape(.rect(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.headline).lineLimit(1)
                                    Text(event.startDate.map { KlangradarDateTime.string($0, format: "dd.MM.yyyy, HH:mm") } ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond") { openRoute() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, minHeight: 50)
                        if let slug = venue.slug {
                            NavigationLink {
                                EntityDetailView(route: EntityRoute(kind: .venue, identifier: slug), repository: repository)
                            } label: {
                                Text("Details ansehen")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                            }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                    }
                }
                .padding(20)
            }
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: repository) }
        }
        .task {
            async let loadedEvents = try? repository.venueEvents(venueID: venue.id, limit: 3)
            if let slug = venue.slug {
                let detail = try? await repository.detail(kind: .venue, identifier: slug)
                venueImageURL = detail?.gallery.first?.url ?? detail?.primaryImageURL
            }
            events = (await loadedEvents) ?? []
        }
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
