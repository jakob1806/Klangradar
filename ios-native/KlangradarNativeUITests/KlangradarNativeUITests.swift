import XCTest

/// Hauptabläufe mit festen Beispieldaten (KLANGRADAR_UI_TEST=1).
/// Ausführen: ios-native/run-ui-tests.sh
@MainActor
final class KlangradarNativeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KLANGRADAR_UI_TEST"] = "1"
        app.launchArguments += ["-didCompleteOnboarding", "YES", "-appearance", "light"]
        // Seit der englischen Oberfläche (String-Katalog) heißen die Tabs auf
        // englischen Simulatoren „Search“ usw. – Tests laufen immer auf Deutsch.
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        // Systemabfragen (Mitteilungen, Standort) auf frischen Simulatoren
        // wegtippen, damit sie die App nicht verdecken.
        addUIInterruptionMonitor(withDescription: "Systemabfrage") { alert in
            for label in ["Erlauben", "Beim Verwenden der App erlauben", "Allow", "Allow While Using App", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app.launch()
    }

    /// Tab antippen. Ab iOS 26 (Liquid-Glass-Tab-Leiste) sind die Tabs teils
    /// keine „Button“-Elemente mehr; dann über das Label (beliebiger Typ) und
    /// als letzter Ausweg über die Position in der Tab-Leiste.
    private func tapTab(_ name: String) {
        let order = ["Home", "Suche", "Karte", "Kalender", "Profil"]
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 10)
        // Englische Bezeichnung mitprüfen, falls die App doch englisch startet.
        let english = ["Home": "Home", "Suche": "Search", "Karte": "Map", "Kalender": "Calendar", "Profil": "Profile"][name] ?? name
        let byLabel = NSPredicate(format: "label == %@ OR label == %@ OR identifier == %@", name, english, name)
        let inBar = tabBar.descendants(matching: .any).matching(byLabel).firstMatch
        if inBar.waitForExistence(timeout: 3), inBar.isHittable { inBar.tap(); return }
        let anywhere = app.descendants(matching: .any).matching(byLabel).firstMatch
        if anywhere.exists, anywhere.isHittable { anywhere.tap(); return }
        print("Tab \(name) nicht gefunden – Tab-Leiste:\n\(tabBar.debugDescription)")
        let index = CGFloat(order.firstIndex(of: name) ?? 0)
        let dx = (index + 0.5) / CGFloat(order.count)
        tabBar.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    func testAllTabsOpen() {
        let tabBar = app.tabBars.firstMatch
        // 06.11.2026: Auf einem frisch angelegten Simulator (nach Xcode-
        // Update) braucht der erste Start deutlich länger; bei Misserfolg
        // die sichtbare Oberfläche ins Log schreiben.
        if !tabBar.waitForExistence(timeout: 60) {
            print("Tab-Leiste fehlt – sichtbar ist:\n\(app.debugDescription)")
            XCTFail("Tab-Leiste nach 60 s nicht sichtbar")
            return
        }
        for (tab, marker) in [("Suche", "Suche"), ("Karte", "Karte"), ("Kalender", "Kalender"), ("Profil", "Profil"), ("Home", "Klangradar")] {
            tapTab(tab)
            XCTAssertTrue(app.staticTexts[marker].firstMatch.waitForExistence(timeout: 15) || app.navigationBars[marker].exists, "Tab \(tab) zeigt keinen Inhalt")
        }
    }

    func testHomeOpensEventDetail() {
        let hero = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Symphonie fantastique")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        hero.tap()
        XCTAssertTrue(app.staticTexts["Symphonie fantastique"].firstMatch.waitForExistence(timeout: 15))
    }

    func testCalendarMonthNavigation() {
        tapTab("Kalender")
        let next = app.buttons["Nächster Monat"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        app.buttons["Vorheriger Monat"].tap()
        XCTAssertTrue(app.staticTexts["Kalender"].firstMatch.exists)
    }

    func testSearchAcceptsInput() {
        tapTab("Suche")
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Bach")
        XCTAssertTrue((field.value as? String)?.hasPrefix("B") == true, "Suchfeld nimmt keine Eingabe an")
    }

    func testPlusPaywallOpensAndCloses() {
        tapTab("Profil")
        let plus = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Klangradar Plus")).firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        XCTAssertTrue(app.staticTexts["Mehr aus jedem Konzertabend."].waitForExistence(timeout: 15))
        app.buttons["Schließen"].tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
    }
}
