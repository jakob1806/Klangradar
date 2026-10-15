import XCTest
@testable import KlangradarNative

/// Hörprobe auf der Werkseite: deutsche Werktitel müssen auf englische
/// Tracktitel passen, und Werknummern müssen exakt stimmen (sonst lieber keine
/// Hörprobe als die falsche Sinfonie).
final class MusicPreviewMatchingTests: XCTestCase {
    func testGermanTitleIsNormalized() {
        XCTAssertEqual(MusicPreview.normalized("Sinfonie Nr. 4 e-Moll"), "symphony no. 4 e-moll")
        XCTAssertEqual(MusicPreview.normalized("Klavierkonzert Nr. 2"), "piano concerto no. 2")
    }

    func testCatalogMarkers() {
        XCTAssertEqual(MusicPreview.catalogMarkers(in: "Sinfonie Nr. 4 e-Moll op. 98"), ["no 4", "op 98"])
        XCTAssertEqual(MusicPreview.catalogMarkers(in: "Matthäus-Passion BWV 244"), ["bwv 244"])
        XCTAssertEqual(MusicPreview.catalogMarkers(in: "Die Zauberflöte K. 620"), ["kv 620"])
        XCTAssertEqual(MusicPreview.catalogMarkers(in: "Second movement 2"), [])
    }

    func testDifferentNumberDoesNotMatch() {
        let title = Set(MusicPreview.catalogMarkers(in: "Symphonie Nr. 2"))
        let track = Set(MusicPreview.catalogMarkers(in: "Symphony No. 5 in C-Sharp Minor: IV. Adagietto"))
        XCTAssertFalse(title.isSubset(of: track))
    }
}
