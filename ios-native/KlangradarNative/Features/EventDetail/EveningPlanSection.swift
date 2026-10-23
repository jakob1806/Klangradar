import SwiftUI
import MapKit

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
    @State private var travel: TravelEstimate?

    private struct TravelEstimate {
        let minutes: Int
        let mode: String
        let label: String
        let symbol: String
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Dein Konzertabend").font(.title2.bold())
                LiquidGlassSurface(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        timeline
                        Divider()
                        travelButtons
                        if !restaurants.isEmpty {
                            Divider()
                            restaurantList
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task { await search() }
        }
    }

    // MARK: Zeitplan

    @ViewBuilder private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let doors = detail.string("doors_info"), !doors.isEmpty {
                timelineRow(symbol: "door.left.hand.open", label: "Einlass", value: doors)
            }
            if let startDate {
                timelineRow(symbol: "music.note", label: "Beginn", value: "\(KlangradarDateTime.string(startDate, format: "HH:mm")) Uhr")
            }
            if detail.bool("has_intermission") == true {
                timelineRow(symbol: "cup.and.saucer", label: "Pause", value: "ja, mit Pause")
            }
            if let endDate {
                timelineRow(symbol: "moon.stars", label: "Ende", value: "ca. \(KlangradarDateTime.string(endDate, format: "HH:mm")) Uhr")
            }
            if let startDate, let travel {
                timelineRow(
                    symbol: "figure.walk.departure",
                    label: "Los",
                    value: "\(KlangradarDateTime.string(startDate.addingTimeInterval(TimeInterval(-(travel.minutes + 25) * 60)), format: "HH:mm")) Uhr · \(travel.minutes) Min. \(travel.label)"
                )
            }
            if let startDate {
                timelineRow(
                    symbol: "clock.badge.checkmark",
                    label: "Tipp",
                    value: arrivalTip(startDate)
                )
            }
        }
    }

    /// Hinweis je nach Uhrzeit und Abend: früher Beginn, Matinee, Pause, langer Abend.
    private func arrivalTip(_ start: Date) -> String {
        let arrive = KlangradarDateTime.string(start.addingTimeInterval(-25 * 60), format: "HH:mm")
        let hour = Calendar.current.component(.hour, from: start)
        var tip = "Gegen \(arrive) Uhr da sein – Garderobe und Programmheft"
        if hour < 14 {
            tip += "; danach bietet sich ein Mittagessen in der Nähe an"
        } else if hour >= 19, let dinner = Calendar.current.date(byAdding: .minute, value: -120, to: start) {
            tip += "; wer vorher essen will, reserviert für \(KlangradarDateTime.string(dinner, format: "HH:mm")) Uhr"
        } else if hour < 19 {
            tip += "; nach dem Konzert bleibt Zeit fürs Abendessen"
        }
        if detail.bool("has_intermission") == true {
            tip += ". Pausengetränk vorab an der Bar bestellen spart Schlange"
        }
        if let endDate, Calendar.current.component(.hour, from: endDate) >= 23 {
            tip += ". Spätes Ende: letzte Verbindung vorher prüfen"
        }
        return tip + "."
    }

    private func timelineRow(symbol: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(KlangradarTheme.accent)
                .frame(width: 22)
            Text(label).font(.subheadline.weight(.semibold)).frame(width: 58, alignment: .leading)
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Anreise

    private var travelButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anreise").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                travelButton("ÖPNV", symbol: "tram.fill", mode: MKLaunchOptionsDirectionsModeTransit)
                travelButton("Zu Fuß", symbol: "figure.walk", mode: MKLaunchOptionsDirectionsModeWalking)
                travelButton("Auto", symbol: "car.fill", mode: MKLaunchOptionsDirectionsModeDriving)
            }
        }
    }

    private func travelButton(_ title: String, symbol: String, mode: String) -> some View {
        Button {
            Haptics.light()
            openDirections(mode: mode)
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(restaurantHeading).font(.subheadline.weight(.semibold))
            ForEach(restaurants, id: \.self) { item in
                Button {
                    item.openInMaps()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(for: item))
                            .foregroundStyle(KlangradarTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Restaurant").font(.subheadline).foregroundStyle(.primary)
                            if let distance = distanceText(to: item) {
                                Text(distance).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
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
        return "\(distance) · \(walkMinutes) Min. zu Fuß"
    }

    private func search() async {
        guard !didSearch, let venueQuery else { return }
        didSearch = true

        let venueRequest = MKLocalSearch.Request()
        venueRequest.naturalLanguageQuery = venueQuery
        venueRequest.resultTypes = [.pointOfInterest, .address]
        guard let found = try? await MKLocalSearch(request: venueRequest).start().mapItems.first else { return }
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

    /// Fahrzeit vom aktuellen Standort, nur wenn die Freigabe schon erteilt
    /// ist (kein neuer Dialog). Bis 2 km zu Fuß, sonst ÖPNV, Auto als Rückfall.
    private func estimateTravel(to destination: MKMapItem) async {
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        let candidates: [(MKDirectionsTransportType, String, String, String)] = [
            (.walking, MKLaunchOptionsDirectionsModeWalking, "zu Fuß", "figure.walk"),
            (.transit, MKLaunchOptionsDirectionsModeTransit, "mit ÖPNV", "tram.fill"),
            (.automobile, MKLaunchOptionsDirectionsModeDriving, "mit dem Auto", "car.fill")
        ]
        for (type, mode, label, symbol) in candidates {
            let request = MKDirections.Request()
            request.source = .forCurrentLocation()
            request.destination = destination
            request.transportType = type
            if let startDate { request.arrivalDate = startDate.addingTimeInterval(-25 * 60) }
            guard let eta = try? await MKDirections(request: request).calculateETA() else { continue }
            let minutes = max(1, Int((eta.expectedTravelTime / 60).rounded()))
            if type == .walking && eta.distance > 2000 { continue }
            travel = TravelEstimate(minutes: minutes, mode: mode, label: label, symbol: symbol)
            return
        }
    }
}
