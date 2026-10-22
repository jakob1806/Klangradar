import XCTest
@testable import KlangradarNative

final class ImageCacheTests: XCTestCase {
    func testWikimediaOriginalBecomesThumbnail() {
        let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/ab/Kent_Nagano_2016.jpg")!
        XCTAssertEqual(ImageCache.sizedURL(url, maxPixel: 300).absoluteString,
                       "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Kent_Nagano_2016.jpg/320px-Kent_Nagano_2016.jpg")
    }

    func testOtherURLsUnchanged() {
        for raw in ["https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/X.jpg/320px-X.jpg",
                    "https://upload.wikimedia.org/wikipedia/commons/a/ab/Logo.svg",
                    "https://zqgzcspeqllrihfwmayn.supabase.co/storage/v1/object/public/images/a.jpg"] {
            let url = URL(string: raw)!
            XCTAssertEqual(ImageCache.sizedURL(url, maxPixel: 300), url)
        }
    }
}
