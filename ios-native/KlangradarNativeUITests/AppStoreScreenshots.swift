import XCTest

/// App-Store-Screenshots mit echten Daten (nicht die Beispieldaten der
/// übrigen UI-Tests). Läuft nur über Scripts/capture-app-store-screenshots.sh,
/// das SCREENSHOT_DIR setzt; im normalen Testlauf wird der Test übersprungen.
@MainActor
final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var outputDirectory: URL!

    override func setUp() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Nur für Scripts/capture-app-store-screenshots.sh")
        }
        continueAfterFailure = true
        outputDirectory = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments += ["-didCompleteOnboarding", "YES", "-appearance", "light"]
        app.launch()
    }

    func testCaptureScreens() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))
        settle(6)
        shoot("01-home")

        // Konzertseite: erste Karte im Home-Feed.
        let firstEvent = app.scrollViews.firstMatch.buttons.element(boundBy: 0)
        if firstEvent.waitForExistence(timeout: 5) {
            firstEvent.tap()
            settle(4)
            shoot("02-konzert")
            // Zurück-Button oben links (eigener Button, keine Navigationsleiste).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.085, dy: 0.068)).tap()
            settle(2)
        }

        tabBar.buttons["Kalender"].tap()
        settle(4)
        shoot("03-kalender")

        tabBar.buttons["Karte"].tap()
        settle(6)
        shoot("04-karte")

        tabBar.buttons["Suche"].tap()
        settle(4)
        shoot("05-suche")

        tabBar.buttons["Profil"].tap()
        let plus = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Klangradar Plus")).firstMatch
        if plus.waitForExistence(timeout: 5) {
            plus.tap()
            settle(3)
            shoot("06-plus")
        }
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shoot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
