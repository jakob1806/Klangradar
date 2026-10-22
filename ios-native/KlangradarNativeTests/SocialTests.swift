import XCTest
@testable import KlangradarNative

final class SocialTests: XCTestCase {
    func testPhoneNormalization() {
        XCTAssertEqual(ContactHashing.normalizedPhone("0170 1234567"), "+491701234567")
        XCTAssertEqual(ContactHashing.normalizedPhone("+49 (170) 123-4567"), "+491701234567")
        XCTAssertEqual(ContactHashing.normalizedPhone("0043 660 1234567"), "+436601234567")
        XCTAssertNil(ContactHashing.normalizedPhone("112"))
    }

    func testEmailHashIsLowercaseHexSha256() {
        // Muss zu encode(sha256(convert_to(lower(trim(email)), 'UTF8')), 'hex') passen.
        XCTAssertEqual(ContactHashing.hash(ContactHashing.normalizedEmail(" Anna@Example.de ")), ContactHashing.hash("anna@example.de"))
        XCTAssertEqual(ContactHashing.hash("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @MainActor
    func testInviteLinkRoutesToFriendCode() {
        let router = DeepLinkRouter.shared
        router.pendingFriendCode = nil
        XCTAssertTrue(router.handle(url: URL(string: "https://klangradar.com/f/abcd2345")!))
        XCTAssertEqual(router.pendingFriendCode, "ABCD2345")
        router.pendingFriendCode = nil
        XCTAssertTrue(router.handle(route: "/plans"))
        XCTAssertEqual(router.pendingFriendsTab, .plans)
        router.pendingFriendsTab = nil
    }

    func testInviteMessageContainsLinkAndCode() {
        let text = FriendInvite.message(code: "ABCD2345")
        XCTAssertTrue(text.contains("https://klangradar.com/f/ABCD2345"))
        XCTAssertTrue(text.contains("ABCD2345"))
    }
}
