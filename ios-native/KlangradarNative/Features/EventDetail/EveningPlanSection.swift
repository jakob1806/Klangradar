import SwiftUI
import MapKit
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

/// Abendplanung auf der Konzertseite: Zeitplan (Einlass, Beginn, Pause, Ende),
/// Anreise mit ÖPNV/zu Fuß/Auto über Apple Maps und Restaurants in der Nähe.
/// Mit Standortfreigabe: echte Fahrzeit (ÖPNV, sonst zu Fuß/Auto) und eine
/// konkrete Losgeh-Zeit; Restaurant-Tipp passend zur Uhrzeit (vorher/danach).
/// Die Spielstätte wird über ihre Adresse mit MapKit gesucht, weil die
/// Detailabfrage keine Koordinaten liefert (venues.location ist geography).
struct EveningPlanSection: View {
    let event: ConcertEvent
    let detail: JSONObject

    @State private var venueItem: MKMapItem?
    @State private var restaurants: [MKMapItem] = []
    @State private var didSearch = false
    @State private var etas: [String: TravelETA] = [:]
    @State private var locationStatus = CLLocationManager().authorizationStatus
    @State private var isEstimating = false
    @State private var locationManager: CLLocationManager?
    @State private var lastOrigin: CLLocation?
    @State private var lastEstimate: Date?
    @Environment(\.scenePhase) private var scenePhase
    @State private var ticketImage: UIImage?
    @State private var ticketPick: PhotosPickerItem?
    @State private var showsTicket = false
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false

    /// Fahrzeit je Verkehrsmittel (Schlüssel: MKLaunchOptionsDirectionsMode*).
    private struct TravelETA {
        let minutes: Int
        let meters: Double
        /// true = aus der Entfernung geschätzt, weil MapKit für ÖPNV keine
        /// Verbindung lieferte (in manchen Regionen/Uhrzeiten der Fall).
        let estimated: Bool
    }

    /// Empfehlung: zu Fuß bis 20 Min., sonst ÖPNV, wenn nicht deutlich
    /// langsamer als das Auto (Auto bekommt 10 Min. für die Parkplatzsuche
    /// dazu), sonst Auto.
    private var recommendation: (mode: String, label: String, minutes: Int, buffer: Int)? {
        let walk = etas[MKLaunchOptionsDirectionsModeWalking]
        let transit = etas[MKLaunchOptionsDirectionsModeTransit]
        let car = etas[MKLaunchOptionsDirectionsModeDriving]
        if let walk, walk.minutes <= 20 { return (MKLaunchOptionsDirectionsModeWalking, "zu Fuß", walk.minutes, 0) }
        if let transit, car.map({ transit.minutes <= $0.minutes + 10 + 20 }) ?? true {
            return (MKLaunchOptionsDirectionsModeTransit, "mit ÖPNV", transit.minutes, 5)
        }
        if let car { return (MKLaunchOptionsDirectionsModeDriving, "mit dem Auto", car.minutes, 10) }
        if let walk { return (MKLaunchOptionsDirectionsModeWalking, "zu Fuß", walk.minutes, 0) }
        return nil
    }

    /// Ankunft vor Beginn: 20 Min. (Garderobe, Platz), bei Einlass-Angabe
    /// mit Uhrzeit (z. B. "Einlass 18:30") diese Uhrzeit.
    private var arrivalTarget: Date? {
        guard let startDate else { return nil }
        if let doors = detail.string("doors_info"),
           let match = doors.firstMatch(of: /(\d{1,2})[:.](\d{2})/),
           let hour = Int(match.1), let minute = Int(match.2),
           let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: startDate),
           date < startDate, startDate.timeIntervalSince(date) <= 90 * 60 {
            return date
        }
        return startDate.addingTimeInterval(-20 * 60)
    }

    private var venue: JSONObject? { detail.object("venues") }

    private var venueQuery: String? {
        guard let venue else { return nil }
        let parts: [String?] = [
            venue.string("name"),
            venue.string("address_street"),
            [venue.string("address_zip"), venue.string("address_city")].compactMap { $0 }.joined(separator: " ")
        ]
        let query = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return query.isEmpty ? nil : query
    }

    private var startDate: Date? { event.startDate }

    private var endDate: Date? {
        if let raw = detail.string("end_datetime"), let date = FlexibleDateParser.date(from: raw) { return date }
        guard let startDate, let minutes = detail.integer("duration_minutes"), minutes > 0 else { return nil }
        return startDate.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private var isUpcoming: Bool {
        guard let startDate else { return false }
        return startDate > Date().addingTimeInterval(-3 * 3600)
    }

    var body: some View {
        if isUpcoming, venueQuery != nil {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dein Konzertabend").font(.title2.bold())
                    Spacer()
                    if let countdown { Text(countdown).font(.subheadline.weight(.semibold)).foregroundStyle(KlangradarTheme.accent) }
                }
                LiquidGlassSurface(cornerRadius: 26) {
                    VStack(alignment: .leading, spacing: 0) {
                        venueMap
                        travelButtons
                            .padding(16)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    ticketCard
                    if !goodToKnow.isEmpty { goodToKnowCard }
                }
                if !restaurants.isEmpty { restaurantList }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task { await search() }
            .task { ticketImage = TicketStore.image(for: event.id) }
            .onChange(of: ticketPick) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        TicketStore.save(image, for: event.id)
                        ticketImage = image
                        Haptics.confirm()
                    }
                    ticketPick = nil
                }
            }
            .photosPicker(isPresented: $showsPhotoPicker, selection: $ticketPick, matching: .images)
            .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .image]) { result in
                guard case let .success(url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let image = Self.ticketImage(from: url) {
                    TicketStore.save(image, for: event.id)
                    ticketImage = image
                    Haptics.confirm()
                }
            }
            .fullScreenCover(isPresented: $showsTicket) {
                if let ticketImage { TicketFullScreen(image: ticketImage) { showsTicket = false } onRemove: {
                    TicketStore.remove(for: event.id); self.ticketImage = nil; showsTicket = false
                } }
            }
            .task(id: venueItem?.placemark.coordinate.latitude) { await followLocation() }
            .onChange(of: scenePhase) { _, phase in
                // Zurück in der App: Standort kann sich geändert haben.
                guard phase == .active, let venueItem else { return }
                Task { await estimateTravel(to: venueItem) }
            }
        }
    }

    // MARK: Karte & Countdown

    /// "Heute · in 2 Std. 10 Min.", "Morgen", "In 5 Tagen".
    private var countdown: String? {
        guard let startDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: startDate)).day ?? 0
        switch days {
        case ..<0: return nil
        case 0:
            let minutes = Int(startDate.timeIntervalSinceNow / 60)
            if minutes <= 0 { return "Läuft gerade" }
            return minutes < 60 ? "Heute · in \(minutes) Min." : "Heute · in \(minutes / 60) Std. \(minutes % 60) Min."
        case 1: return "Morgen"
        default: return "In \(days) Tagen"
        }
    }

    @ViewBuilder private var venueMap: some View {
        if let venueItem {
            Map(initialPosition: .region(MKCoordinateRegion(center: venueItem.placemark.coordinate, latitudinalMeters: 900, longitudinalMeters: 900)), interactionModes: []) {
                Marker(venue?.string("name") ?? "Spielstätte", systemImage: "music.note", coordinate: venueItem.placemark.coordinate)
                    .tint(KlangradarTheme.accent)
                ForEach(restaurants, id: \.self) { item in
                    Marker(item.name ?? "", systemImage: symbol(for: item), coordinate: item.placemark.coordinate)
                        .tint(.orange)
                }
            }
            .frame(height: 150)
            .allowsHitTesting(false)
            .overlay(alignment: .bottomLeading) {
                Text(venue?.string("name") ?? "")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: .capsule)
                    .padding(10)
            }
        }
    }

    // MARK: Anreise

    private var travelButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                travelButton("ÖPNV", symbol: "tram.fill", mode: MKLaunchOptionsDirectionsModeTransit)
                travelButton("Zu Fuß", symbol: "figure.walk", mode: MKLaunchOptionsDirectionsModeWalking)
                travelButton("Auto", symbol: "car.fill", mode: MKLaunchOptionsDirectionsModeDriving)
            }
            if locationStatus == .notDetermined {
                Button {
                    requestLocation()
                } label: {
                    Label("Fahrzeit von meinem Standort berechnen", systemImage: "location")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(KlangradarTheme.accent)
            } else if isEstimating {
                Text("Fahrzeiten werden berechnet …").font(.footnote).foregroundStyle(.secondary)
            } else if etas[MKLaunchOptionsDirectionsModeTransit]?.estimated == true {
                Text("ÖPNV-Zeit geschätzt – die genaue Verbindung zeigt Apple Karten.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func requestLocation() {
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()
        Task {
            // Auf die Antwort im Systemdialog warten (kein Delegate nötig).
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                let status = manager.authorizationStatus
                if status != .notDetermined {
                    locationStatus = status
                    if let venueItem { await estimateTravel(to: venueItem) }
                    return
                }
            }
        }
    }

    private func travelButton(_ title: String, symbol: String, mode: String) -> some View {
        Button {
            Haptics.light()
            openDirections(mode: mode)
        } label: {
            VStack(spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                if let eta = etas[mode] {
                    Text("\(eta.estimated ? "ca. " : "")\(eta.minutes) Min.")
                        .font(.caption.monospacedDigit())
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(recommendation?.mode == mode ? Color.white : Color.primary)
            .background(
                recommendation?.mode == mode ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                in: .rect(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(recommendation?.mode == mode ? "Empfohlen. Öffnet die Route in Apple Karten." : "Öffnet die Route in Apple Karten.")
    }

    private func openDirections(mode: String) {
        if let venueItem {
            venueItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
            return
        }
        // Fallback, solange die Suche noch läuft oder nichts gefunden hat.
        guard let query = venueQuery?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let flag = switch mode {
        case MKLaunchOptionsDirectionsModeTransit: "r"
        case MKLaunchOptionsDirectionsModeWalking: "w"
        default: "d"
        }
        if let url = URL(string: "maps://?daddr=\(query)&dirflg=\(flag)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Restaurants

    private var restaurantList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(restaurantHeading).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(restaurants, id: \.self) { item in
                        PlaceCard(item: item, symbol: symbol(for: item), color: placeColor(for: item), distance: distanceText(to: item))
                    }
                }
            }
        }
    }

    /// Kategoriefarben wie in Apple Karten (Essen orange, Café braun, Bar lila).
    private func placeColor(for item: MKMapItem) -> Color {
        switch item.pointOfInterestCategory {
        case .cafe?, .bakery?: Color(red: 0.64, green: 0.45, blue: 0.29)
        case .brewery?, .winery?, .nightlife?: Color(red: 0.69, green: 0.32, blue: 0.87)
        default: Color(red: 1.0, green: 0.58, blue: 0.0)
        }
    }

    private var restaurantHeading: String {
        guard let startDate else { return "Essen & Trinken in der Nähe" }
        let hour = Calendar.current.component(.hour, from: startDate)
        if hour < 14 { return "Nach der Matinee: Essen in der Nähe" }
        return hour >= 19 ? "Vorher essen gehen" : "Danach noch einkehren"
    }

    private func symbol(for item: MKMapItem) -> String {
        switch item.pointOfInterestCategory {
        case .cafe?: "cup.and.saucer.fill"
        case .bakery?: "birthday.cake.fill"
        case .brewery?, .winery?, .nightlife?: "wineglass.fill"
        default: "fork.knife"
        }
    }

    private func distanceText(to item: MKMapItem) -> String? {
        guard let from = venueItem?.placemark.location, let to = item.placemark.location else { return nil }
        let meters = from.distance(from: to)
        let walkMinutes = max(1, Int((meters / 80).rounded()))
        let distance = meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
        return "\(walkMinutes) Min. · \(distance)"
    }

    private func search() async {
        guard !didSearch, let venueQuery else { return }
        didSearch = true

        guard let found = await locateVenue(fallbackQuery: venueQuery) else { return }
        venueItem = found

        await estimateTravel(to: found)

        let poiRequest = MKLocalPointsOfInterestRequest(center: found.placemark.coordinate, radius: 600)
        poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .brewery, .winery])
        guard let response = try? await MKLocalSearch(request: poiRequest).start() else { return }
        let origin = CLLocation(latitude: found.placemark.coordinate.latitude, longitude: found.placemark.coordinate.longitude)
        restaurants = response.mapItems
            .filter { $0.name != found.name }
            .sorted {
                origin.distance(from: $0.placemark.location ?? origin) < origin.distance(from: $1.placemark.location ?? origin)
            }
            .prefix(4)
            .map { $0 }
    }

    /// Spielstätte finden: zuerst über die reine Postadresse (Straße, PLZ,
    /// Ort – exakter Punkt), erst ohne Adresse über die Freitextsuche mit
    /// Namen, die öfter einen falschen Ort traf (Nutzermeldung 24.10.2026).
    private func locateVenue(fallbackQuery: String) async -> MKMapItem? {
        let address = [venue?.string("address_street"),
                       [venue?.string("address_zip"), venue?.string("address_city")].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if venue?.string("address_street")?.isEmpty == false,
           let placemark = try? await CLGeocoder().geocodeAddressString(address).first,
           let location = placemark.location {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
            item.name = venue?.string("name")
            return item
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = fallbackQuery
        request.resultTypes = [.pointOfInterest, .address]
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    /// Fahrzeiten vom aktuellen Standort für alle drei Verkehrsmittel, mit Ankunftszeit zum Konzert (Verkehrslage/Fahrplan).
    /// Liefert MapKit für ÖPNV nichts, wird aus der Entfernung geschätzt
    /// (Ø 18 km/h Fahrt + 8 Min. Fußweg/Warten), statt still aufs Auto zu
    /// wechseln.
    private func estimateTravel(to destination: MKMapItem, from given: CLLocation? = nil) async {
        let status = CLLocationManager().authorizationStatus
        locationStatus = status
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        isEstimating = etas.isEmpty
        defer { isEstimating = false }
        var origin = given
        if origin == nil { origin = await currentLocation() }
        guard let here = origin else { return }
        lastOrigin = here
        lastEstimate = Date()
        let source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
        func eta(_ type: MKDirectionsTransportType) async -> (expectedTravelTime: TimeInterval, distance: Double)? {
            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = type
            // Immer "Abfahrt jetzt vom aktuellen Standort": Mit arrivalDate
            // (Konzertbeginn) rechnete Apple bei ÖPNV die Wartezeit bis zur
            // passenden Verbindung mit ein – z. B. 64 statt real 45 Min.
            // (Nutzermeldung 24.10.2026).
            request.departureDate = Date()
            guard let response = try? await MKDirections(request: request).calculateETA() else { return nil }
            return (response.expectedTravelTime, response.distance)
        }
        // Nacheinander (MKDirections-Antworten sind nicht Sendable); jede
        // Anfrage dauert nur Sekundenbruchteile.
        let walkETA = await eta(.walking)
        let transitETA = await eta(.transit)
        let carETA = await eta(.automobile)

        var result: [String: TravelETA] = [:]
        func minutes(_ seconds: TimeInterval) -> Int { max(1, Int((seconds / 60).rounded())) }
        if let walkETA, walkETA.distance <= 6000 {
            result[MKLaunchOptionsDirectionsModeWalking] = TravelETA(minutes: minutes(walkETA.expectedTravelTime), meters: walkETA.distance, estimated: false)
        }
        if let carETA {
            result[MKLaunchOptionsDirectionsModeDriving] = TravelETA(minutes: minutes(carETA.expectedTravelTime), meters: carETA.distance, estimated: false)
        }
        if let transitETA {
            result[MKLaunchOptionsDirectionsModeTransit] = TravelETA(minutes: minutes(transitETA.expectedTravelTime), meters: transitETA.distance, estimated: false)
        } else {
            let meters = carETA?.distance ?? here.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)) * 1.3
            if meters > 1200 {
                result[MKLaunchOptionsDirectionsModeTransit] = TravelETA(minutes: Int((meters / 1000 / 18 * 60).rounded()) + 8, meters: meters, estimated: true)
            }
        }
        etas = result
        publishPlan()
    }

    /// Losgeh-Zeit an Live Activity und Erinnerung weitergeben.
    private func publishPlan() {
        guard let startDate, let arrival = arrivalTarget, let pick = recommendation else { return }
        let leave = arrival.addingTimeInterval(TimeInterval(-(pick.minutes + pick.buffer) * 60))
        let pause: Date? = detail.bool("has_intermission") == true
            ? endDate.map { startDate.addingTimeInterval($0.timeIntervalSince(startDate) / 2 - 10 * 60) } : nil
        let plan = ConcertDayCoordinator.Plan(
            slug: event.slug, title: event.title, venue: venue?.string("name") ?? event.venueName,
            start: startDate, leaveAt: leave, travel: "\(pick.minutes) Min. \(pick.label)", pauseAt: pause
        )
        Task { await ConcertDayCoordinator.shared.update(plan) }
    }

    // MARK: Ticket & Gut zu wissen

    /// Bild aus Foto-Datei oder erster PDF-Seite (in hoher Auflösung, damit
    /// QR-/Barcodes am Einlass scanbar bleiben).
    private static func ticketImage(from url: URL) -> UIImage? {
        if url.pathExtension.lowercased() == "pdf" || UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2400 / max(bounds.width, bounds.height)
            return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private var ticketCard: some View {
        Group {
            if let ticketImage {
                Button { showsTicket = true } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(uiImage: ticketImage).resizable().scaledToFill()
                            .frame(height: 74).frame(maxWidth: .infinity).clipped()
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                        Label("Ticket öffnen", systemImage: "ticket").font(.subheadline.weight(.semibold))
                    }
                }
            } else {
                Menu {
                    Button("Foto auswählen", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
                    Button("Datei auswählen", systemImage: "doc") { showsFileImporter = true }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "ticket").font(.title2).foregroundStyle(KlangradarTheme.accent)
                        HStack(spacing: 4) {
                            Text("Ticket ablegen").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Text("Foto, Screenshot oder PDF – bleibt nur auf deinem iPhone.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
    }

    /// Einlass/Garderobe, Anreise, Parken, Gastronomie, Barrierefreiheit der
    /// Spielstätte. Platzhaltertexte aus dem Import ("… prüfen") werden
    /// ausgeblendet.
    private var goodToKnow: [(symbol: String, title: String, text: String)] {
        guard let venue else { return [] }
        func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
                  !value.localizedCaseInsensitiveContains("prüfen"), !value.localizedCaseInsensitiveContains("ergänzen") else { return nil }
            return value
        }
        var items: [(String, String, String)] = []
        if let text = clean(venue.string("doors_info_de")) { items.append(("door.left.hand.open", "Einlass & Garderobe", text)) }
        if let text = clean(venue.string("arrival_info_de")) { items.append(("tram", "Anreise", text)) }
        if let text = clean(venue.string("parking_info_de")) { items.append(("parkingsign", "Parken", text)) }
        if let text = clean(venue.string("catering_info_de")) { items.append(("wineglass", "Gastronomie", text)) }
        if let access = venue.object("accessibility"), !access.isEmpty {
            let labels: [(String, String)] = [("wheelchair", "Rollstuhlplätze"), ("step_free", "Stufenloser Zugang"), ("hearing_loop", "Induktionsschleife"), ("elevator", "Aufzug"), ("accessible_toilet", "Barrierefreies WC")]
            let present = labels.filter { access.bool($0.0) == true }.map(\.1)
            if !present.isEmpty { items.append(("figure.roll", "Barrierefrei", present.joined(separator: " · "))) }
        }
        return items
    }

    private var goodToKnowCard: some View {
        Menu {
            ForEach(goodToKnow, id: \.title) { item in
                Section(item.title) { Text(item.text) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "info.circle").font(.title2).foregroundStyle(KlangradarTheme.accent)
                Text("Gut zu wissen").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(goodToKnow.map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    /// Fahrzeit immer vom aktuellen Standort (Nutzerwunsch 24.10.2026):
    /// solange die Seite offen ist, bei mehr als 250 m Bewegung oder alle
    /// 3 Minuten neu berechnen (Fahrplan und Verkehr ändern sich auch).
    private func followLocation() async {
        guard let venueItem, isUpcoming else { return }
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location, location.horizontalAccuracy < 200 else { continue }
                let moved = lastOrigin.map { location.distance(from: $0) > 250 } ?? true
                let stale = lastEstimate.map { Date().timeIntervalSince($0) > 180 } ?? true
                if moved || stale { await estimateTravel(to: venueItem, from: location) }
            }
        } catch {}
    }

    /// Aktueller Standort: zuletzt bekannter, wenn frisch (< 5 Min.), sonst
    /// das erste Update (max. 8 Sek.). Nur Sekunden alt, damit die Fahrzeit
    /// immer vom tatsächlichen Standort aus gilt.
    private func currentLocation() async -> CLLocation? {
        if let cached = CLLocationManager().location, cached.timestamp.timeIntervalSinceNow > -60 { return cached }
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return CLLocationManager().location
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Ticket im Vollbild mit voller Helligkeit (für den Einlass-Scanner).
private struct TicketFullScreen: View {
    let image: UIImage
    let onClose: () -> Void
    let onRemove: () -> Void
    @State private var previousBrightness: CGFloat = 0.5

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                Image(uiImage: image).resizable().scaledToFit().padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fertig", action: onClose) }
                ToolbarItem(placement: .topBarTrailing) { Button("Entfernen", role: .destructive, action: onRemove) }
            }
        }
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        }
        .onDisappear { UIScreen.main.brightness = previousBrightness }
    }
}

/// Ort wie in Apple Karten: Look-Around-Foto, gefüllter Kategorie-Kreis,
/// Name, Fußweg. Tippen öffnet die Apple-Karten-Ortskarte (iOS 18) bzw.
/// Apple Karten.
private struct PlaceCard: View {
    let item: MKMapItem
    let symbol: String
    let color: Color
    let distance: String?

    @State private var photo: UIImage?
    @State private var showsDetail = false

    var body: some View {
        Button {
            if #available(iOS 18.0, *) { showsDetail = true } else { item.openInMaps() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(color.opacity(0.12))
                            .overlay { Image(systemName: symbol).font(.largeTitle).foregroundStyle(color.opacity(0.5)) }
                    }
                    Image(systemName: symbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(color, in: .circle)
                        .overlay { Circle().stroke(.white, lineWidth: 2) }
                        .padding(8)
                }
                .frame(width: 180, height: 110)
                .clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name ?? "Restaurant").font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text([categoryName, distance].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(width: 180, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(MapItemDetailModifier(item: item, isPresented: $showsDetail))
        .task { await loadPhoto() }
    }

    private var categoryName: String? {
        switch item.pointOfInterestCategory {
        case .cafe?: "Café"
        case .bakery?: "Bäckerei"
        case .brewery?: "Brauerei"
        case .winery?: "Weinbar"
        case .nightlife?: "Bar"
        case .restaurant?: "Restaurant"
        default: nil
        }
    }

    private func loadPhoto() async {
        guard photo == nil, let scene = try? await MKLookAroundSceneRequest(mapItem: item).scene else { return }
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 360, height: 220)
        photo = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
    }
}

private struct MapItemDetailModifier: ViewModifier {
    let item: MKMapItem
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.mapItemDetailSheet(isPresented: $isPresented, item: item)
        } else {
            content
        }
    }
}
