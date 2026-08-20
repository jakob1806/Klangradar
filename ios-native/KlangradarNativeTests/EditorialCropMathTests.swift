import XCTest
@testable import KlangradarNative

final class EditorialCropMathTests: XCTestCase {
    func testWiderImageCropsLeftAndRight() {
        // 2:1-Bild in ein 1:1-Ziel (Avatar) — links/rechts wird beschnitten.
        let crop = EditorialCropMath.defaultCrop(naturalWidth: 2000, naturalHeight: 1000, aspect: 1)
        XCTAssertEqual(crop.height, 1, accuracy: 0.0001)
        XCTAssertEqual(crop.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(crop.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(crop.y, 0, accuracy: 0.0001)
    }

    func testTallerImageCropsTopAndBottom() {
        // 1:2-Bild in ein 16:9-Ziel — oben/unten wird beschnitten.
        let crop = EditorialCropMath.defaultCrop(naturalWidth: 1000, naturalHeight: 2000, aspect: 16.0 / 9.0)
        XCTAssertEqual(crop.width, 1, accuracy: 0.0001)
        XCTAssertEqual(crop.x, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(crop.y, 0)
        XCTAssertEqual(crop.y, (1 - crop.height) / 2, accuracy: 0.0001)
    }

    func testResultingRectStaysWithinOriginalImage() {
        let crop = EditorialCropMath.defaultCrop(naturalWidth: 1600, naturalHeight: 900, aspect: 1)
        XCTAssertGreaterThanOrEqual(crop.x, 0)
        XCTAssertGreaterThanOrEqual(crop.y, 0)
        XCTAssertLessThanOrEqual(crop.x + crop.width, 1.0001)
        XCTAssertLessThanOrEqual(crop.y + crop.height, 1.0001)
    }
}
