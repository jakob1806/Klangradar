import XCTest
@testable import KlangradarNative

final class AffiliateRuleTests: XCTestCase {
    func testAppendsParamsOnMatchingHostOnly() {
        let rule = AffiliateRule(hostSuffix: "eventim.de", urlTemplate: nil, appendParams: ["affiliate": "KLR"])
        XCTAssertEqual(rule.rewrite(URL(string: "https://www.eventim.de/event/123?x=1")!)?.absoluteString, "https://www.eventim.de/event/123?x=1&affiliate=KLR")
        XCTAssertNil(rule.rewrite(URL(string: "https://noteventim.de/event/123")!))
        XCTAssertNil(rule.rewrite(URL(string: "https://staatsoper.de/tickets")!))
    }

    func testTemplateWrapsEncodedURL() {
        let rule = AffiliateRule(hostSuffix: "eventim.de", urlTemplate: "https://www.awin1.com/cread.php?awinmid=1&ued={url}", appendParams: [:])
        let result = rule.rewrite(URL(string: "https://www.eventim.de/event/1?a=b")!)?.absoluteString
        XCTAssertEqual(result, "https://www.awin1.com/cread.php?awinmid=1&ued=https%3A%2F%2Fwww%2Eeventim%2Ede%2Fevent%2F1%3Fa%3Db")
    }

    func testExistingParamIsNotDuplicated() {
        let rule = AffiliateRule(hostSuffix: "reservix.de", urlTemplate: nil, appendParams: ["vid": "9"])
        XCTAssertEqual(rule.rewrite(URL(string: "https://reservix.de/t?vid=1")!)?.absoluteString, "https://reservix.de/t?vid=1")
    }
}
