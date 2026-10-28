import XCTest

/// Necesită serverul pornit local (swift run App serve) și permisiunea de locație acordată simulatorului.
final class SaveStoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSavingStoryFromFeedShowsItInProfile() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Pentru tine"].firstMatch.tap()

        let save = visibleButton(labeled: "Salvează", in: app)
        XCTAssertNotNil(save, "Nu găsesc butonul Salvează pe reel-ul afișat")
        save?.tap()

        XCTAssertNotNil(visibleButton(labeled: "Salvat", in: app, timeout: 3), "Butonul nu a trecut în starea Salvat")

        app.buttons["Profil"].firstMatch.tap()
        let emptyHint = app.staticTexts["Apasă pe semnul de carte dintr-un reel ca să-l salvezi aici."]
        XCTAssertFalse(emptyHint.waitForExistence(timeout: 2), "Profilul nu arată povestea salvată")

        // Povestea salvată se deschide pe tot ecranul, iar X o închide.
        let savedRow = app.buttons["profile.savedStory"].firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 3), "Povestea salvată nu apare în Profil")
        savedRow.tap()
        let close = app.buttons["Închide"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Nu s-a deschis reel-ul salvat")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "Butonul X nu a închis reel-ul")

        // Dezactivarea salvării o scoate din Profil.
        app.buttons["Pentru tine"].firstMatch.tap()
        visibleButton(labeled: "Salvat", in: app)?.tap()
        XCTAssertNotNil(visibleButton(labeled: "Salvează", in: app, timeout: 3), "Nu se poate anula salvarea")
    }

    /// Feed-ul randează și paginile vecine, deci alegem butonul de pe pagina vizibilă.
    private func visibleButton(labeled label: String, in app: XCUIApplication, timeout: TimeInterval = 20) -> XCUIElement? {
        let deadline = Date.now.addingTimeInterval(timeout)
        let query = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label))
        repeat {
            if let match = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date.now < deadline
        return nil
    }
}
