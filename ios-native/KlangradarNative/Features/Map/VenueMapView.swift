import MapKit
import SwiftUI

struct VenueMapView: View {
    let repository: any ContentRepository
    let eventRepository: any EventRepository

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
            .presentationDetents([.height(56 + CGFloat((selectedVenueGroup?.count ?? 0)) * 64)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsFilter) { filterSheet }
        .task { venues = (try? await repository.venueLocations()) ?? [] }
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
                Button("Filter", systemImage: "line.3.horizontal.decrease") { showsFilter = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(height: 46)
                    .background(.regularMaterial, in: .capsule)
                    .foregroundStyle(.primary)
                    Spacer()
                Button {
                    Task { await locateUser() }
                } label: {
                    Image(systemName: "location.north.fill")
                        .font(.headline)
                        .foregroundStyle(KlangradarTheme.accent)
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

    @MainActor private func locateUser() async {
        do {
            let coordinate = try await locationRequester.requestOnce()
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

                    HStack {
                        Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond") { openRoute() }
                            .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                        if let slug = venue.slug {
                            NavigationLink {
                                EntityDetailView(route: EntityRoute(kind: .venue, identifier: slug), repository: repository)
                            } label: { Text("Details ansehen").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent).controlSize(.large)
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
                    HStack {
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
