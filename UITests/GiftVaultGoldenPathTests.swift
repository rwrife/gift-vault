import XCTest

/// Issue #4 golden path: add person → add idea → create occasion →
/// choose idea → mark given → ledger shows the entry. Launches against
/// the fixture vault (`-ui-testing`), which never contains "Nova".
final class GiftVaultGoldenPathTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoldenPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.people"].waitForExistence(timeout: 10))

        // 1. Add person "Nova".
        let peopleTab = app.tabBars.buttons["People"]
        XCTAssertTrue(peopleTab.waitForExistence(timeout: 10))
        peopleTab.tap()
        app.buttons["people.add"].tap()
        XCTAssertTrue(app.sheets["sheet.person"].waitForExistence(timeout: 10))
        app.textFields["person.name"].tap()
        app.textFields["person.name"].typeText("Nova")
        app.sheets["sheet.person"].buttons["person.save"].tap()
        XCTAssertTrue(app.staticTexts["Nova"].waitForExistence(timeout: 10))

        // 2. Add idea with a price hint for Nova.
        app.staticTexts["Nova"].tap()
        XCTAssertTrue(app.otherElements["screen.ideas"].waitForExistence(timeout: 10))
        app.buttons["ideas.add"].tap()
        XCTAssertTrue(app.sheets["sheet.idea"].waitForExistence(timeout: 10))
        app.textFields["idea.note"].tap()
        app.textFields["idea.note"].typeText("Trail daypack")
        app.textFields["idea.price"].tap()
        app.textFields["idea.price"].typeText("45.00")
        app.sheets["sheet.idea"].buttons["idea.save"].tap()
        XCTAssertTrue(app.staticTexts["Trail daypack"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["$45.00"].waitForExistence(timeout: 10))

        // 3. Create occasion "Nova quiz" with a 50 budget, Nova attached.
        app.tabBars.buttons["Occasions"].tap()
        app.buttons["occasions.add"].tap()
        XCTAssertTrue(app.sheets["sheet.occasion"].waitForExistence(timeout: 10))
        app.textFields["occasion.name"].tap()
        app.textFields["occasion.name"].typeText("Nova quiz")
        app.textFields["occasion.budget"].tap()
        app.textFields["occasion.budget"].typeText("50.00")
        let novaToggle = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova")
        ).firstMatch
        XCTAssertTrue(novaToggle.waitForExistence(timeout: 10))
        novaToggle.tap()
        app.sheets["sheet.occasion"].buttons["occasion.save"].tap()
        XCTAssertTrue(app.staticTexts["Nova quiz"].waitForExistence(timeout: 10))

        // 4. Open the board, choose the idea, walk the state machine.
        app.staticTexts["Nova quiz"].tap()
        XCTAssertTrue(app.otherElements["screen.board"].waitForExistence(timeout: 10))
        let chooseButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "board.choose")
        ).firstMatch
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 10))
        chooseButton.tap()
        let pickButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "choose.pick")
        ).firstMatch
        XCTAssertTrue(pickButton.waitForExistence(timeout: 10))
        pickButton.tap()

        // idea → chosen happened via the chooser; now chosen → bought →
        // wrapped → given. The advance button keeps the same identifier
        // across states; tap → Confirm for each legal step.
        let advance = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "board.advance")
        ).firstMatch
        for _ in 0..<3 {
            XCTAssertTrue(advance.waitForExistence(timeout: 10))
            advance.tap()
            let confirm = app.buttons["Confirm"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            confirm.tap()
        }

        // 5. The given transition wrote the implied ledger row.
        app.tabBars.buttons["Ledger"].tap()
        XCTAssertTrue(app.otherElements["screen.ledger"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Given Nova")
            ).firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Trail daypack")
            ).firstMatch.waitForExistence(timeout: 10)
        )
    }
}
