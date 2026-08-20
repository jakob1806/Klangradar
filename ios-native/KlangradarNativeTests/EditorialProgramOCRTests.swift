import XCTest
@testable import KlangradarNative

final class EditorialProgramOCRTests: XCTestCase {
    private let options: [EditorialOption] = [
        EditorialOption(id: UUID(), title: "Ludwig van Beethoven", subtitle: nil),
        EditorialOption(id: UUID(), title: "Münchner Philharmoniker", subtitle: nil),
        EditorialOption(id: UUID(), title: "Sinfonie Nr. 5 c-Moll op. 67", subtitle: "Beethoven"),
    ]

    func testExactMatchIgnoringCase() {
        let match = EditorialProgramOCR.bestMatch(for: "ludwig van beethoven", in: options)
        XCTAssertEqual(match?.title, "Ludwig van Beethoven")
    }

    func testMatchToleratesMinorOCRNoise() {
        // Typische OCR-Abweichung: abgeschnittenes Wortende, andere
        // Diakritika-Schreibweise.
        let match = EditorialProgramOCR.bestMatch(for: "Munchner Philharmonike", in: options)
        XCTAssertEqual(match?.title, "Münchner Philharmoniker")
    }

    func testNoMatchBelowThreshold() {
        let match = EditorialProgramOCR.bestMatch(for: "Pause", in: options)
        XCTAssertNil(match)
    }

    func testEmptyTextNeverMatches() {
        XCTAssertNil(EditorialProgramOCR.bestMatch(for: "   ", in: options))
    }

    func testWorkTitleSubstringMatch() {
        let match = EditorialProgramOCR.bestMatch(for: "Sinfonie Nr. 5", in: options)
        XCTAssertEqual(match?.title, "Sinfonie Nr. 5 c-Moll op. 67")
    }
}
