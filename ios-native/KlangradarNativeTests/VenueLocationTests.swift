import XCTest
@testable import KlangradarNative

final class VenueLocationTests: XCTestCase {
    /// Nutzerfeedback: mehrere Säle am selben Gebäude (Gasteig HP8:
    /// Isarphilharmonie, Saal X, Blackbox) landeten als ein nicht einzeln
    /// antippbarer Kartenpin, weil sie identische Koordinaten haben.
    func testGroupsVenuesAtIdenticalCoordinate() {
        let isarphilharmonie = VenueLocation(id: UUID(), name: "Isarphilharmonie (Gasteig HP8)", latitude: 48.1114407, longitude: 11.553687)
        let saalX = VenueLocation(id: UUID(), name: "Saal X im Gasteig HP8", latitude: 48.1114407, longitude: 11.553687)
        let blackbox = VenueLocation(id: UUID(), name: "Black Box im Gasteig HP8", latitude: 48.1114407, longitude: 11.553687)
        let prinzregententheater = VenueLocation(id: UUID(), name: "Prinzregententheater", latitude: 48.1447, longitude: 11.5993)

        let groups = groupVenuesByLocation([isarphilharmonie, saalX, blackbox, prinzregententheater])

        XCTAssertEqual(groups.count, 2)
        let sizes = groups.map(\.count).sorted()
        XCTAssertEqual(sizes, [1, 3])
        let gasteigGroup = groups.first { $0.count == 3 }
        XCTAssertEqual(Set(gasteigGroup?.map(\.name) ?? []), [isarphilharmonie.name, saalX.name, blackbox.name])
    }

    func testKeepsNearbyButDistinctVenuesSeparate() {
        // ~1.1km auseinander (0.01° Breite) — klar unterschiedliche Orte,
        // dürfen NICHT zusammengefasst werden, nur weil sie beide "in der
        // Nähe" liegen.
        let a = VenueLocation(id: UUID(), name: "Venue A", latitude: 48.1374, longitude: 11.5755)
        let b = VenueLocation(id: UUID(), name: "Venue B", latitude: 48.1474, longitude: 11.5755)

        let groups = groupVenuesByLocation([a, b])

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.count == 1 })
    }

    func testSingleVenueFormsItsOwnGroup() {
        let venue = VenueLocation(id: UUID(), name: "Solo Venue", latitude: 48.0, longitude: 11.0)
        let groups = groupVenuesByLocation([venue])
        XCTAssertEqual(groups, [[venue]])
    }

    /// Nutzerfeedback: der Gruppen-Pin für Gasteig HP8 zeigte "Black Box im
    /// Gasteig HP8" (Name des ersten Venues) als Übertitel statt des
    /// gemeinsamen Gebäudenamens "Gasteig HP8".
    func testGroupTitleExtractsSharedBuildingName() {
        let isarphilharmonie = VenueLocation(id: UUID(), name: "Isarphilharmonie (Gasteig HP8)", latitude: 48.1114407, longitude: 11.553687)
        let saalX = VenueLocation(id: UUID(), name: "Saal X im Gasteig HP8", latitude: 48.1114407, longitude: 11.553687)
        let blackbox = VenueLocation(id: UUID(), name: "Black Box im Gasteig HP8", latitude: 48.1114407, longitude: 11.553687)

        XCTAssertEqual(titleForVenueGroup([blackbox, isarphilharmonie, saalX]), "Gasteig HP8")
    }

    func testGroupTitleFallsBackToCountWithoutSharedName() {
        let a = VenueLocation(id: UUID(), name: "Alpha Saal", latitude: 48.0, longitude: 11.0)
        let b = VenueLocation(id: UUID(), name: "Beta Bühne", latitude: 48.0, longitude: 11.0)

        XCTAssertEqual(titleForVenueGroup([a, b]), "2 Konzertorte")
    }
}
