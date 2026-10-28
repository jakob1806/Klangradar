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

final class EmailLinkTests: XCTestCase {
    @MainActor
    func testEmailEventLinkOpensEvent() {
        let router = DeepLinkRouter.shared
        router.pendingEventSlug = nil
        XCTAssertTrue(router.handle(url: URL(string: "https://klangradar.com/e/mahler-2")!))
        XCTAssertEqual(router.pendingEventSlug, "mahler-2")
        router.pendingEventSlug = nil
    }
}

/// Freunde-Ausbau 28.10.2026: QR-Code und Anfragen-Kontext.
final class FriendsProcessTests: XCTestCase {
    func testFriendCodeParserAcceptsLinkSchemeAndRawCode() {
        XCTAssertEqual(FriendCodeParser.code(from: "https://klangradar.com/f/abcd2345"), "ABCD2345")
        XCTAssertEqual(FriendCodeParser.code(from: "de.klangradar.native://friend/ABCD2345"), "ABCD2345")
        XCTAssertEqual(FriendCodeParser.code(from: "  abcd2345 \n"), "ABCD2345")
        XCTAssertNil(FriendCodeParser.code(from: "https://example.com/f/ABCD2345"))
        XCTAssertNil(FriendCodeParser.code(from: "ABC"))
        XCTAssertNil(FriendCodeParser.code(from: "Hallo Welt!"))
    }

    func testQRCodeEncodesInviteLink() {
        XCTAssertNotNil(FriendQRCode.image(for: FriendInvite.link(code: "ABCD2345").absoluteString))
    }

    func testRequestContextLine() {
        let person = SocialPerson(id: UUID(), name: "Lena", avatarURL: nil)
        let concert = FriendRequest(person: person, incoming: true, mutualFriends: 0, source: "concert", sharedComposers: ["Mahler", "Bruckner"], context: "Mahler 2 am 26.10.")
        XCTAssertEqual(concert.contextLine, "Wart beide bei Mahler 2 am 26.10.")
        XCTAssertEqual(concert.composersLine, "Ihr hört beide gern Mahler und Bruckner")
        XCTAssertNil(FriendRequest(person: person, incoming: true, mutualFriends: 0).contextLine)
    }
}
