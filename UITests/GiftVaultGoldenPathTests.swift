import XCTest

/// Issue #4 golden path: add person → add idea → create occasion →
/// choose idea → mark given → ledger shows the entry. Launches against
/// the fixture vault (`-ui-testing`), which never contains "Nova".
///
/// Query strategy: SwiftUI merges Button/label content into one
/// accessibility element, so list rows are located by button-label
/// CONTAINS or by the accessibilityIdentifier set on the control —
/// never by child staticTexts inside a button label. Plain (non-button)
/// texts (ledger rows, list-row texts under NavigationLinks) are safe
/// staticTexts queries.
final class GiftVaultGoldenPathTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Screen identifiers are attached to List/Group containers whose
    /// XCUITest element type is not guaranteed to be `otherElements`, so
    /// match them by identifier across every element type.
    @MainActor
    private func waitForScreen(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) {
        let screen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", id))
            .firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: timeout), "screen \(id) not found")
    }

    @MainActor
    func testGoldenPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        waitForScreen(app, "screen.people")

        // 1. Add person "Nova".
        let peopleTab = app.tabBars.buttons["People"]
        XCTAssertTrue(peopleTab.waitForExistence(timeout: 10))
        peopleTab.tap()
        app.buttons["people.add"].tap()
        XCTAssertTrue(app.buttons["person.save"].waitForExistence(timeout: 10))
        app.textFields["person.name"].tap()
        app.textFields["person.name"].typeText("Nova")
        app.buttons["person.save"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Nova")
            ).firstMatch.waitForExistence(timeout: 10)
        )

        // 2. Add idea with a price hint for Nova.
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova")
        ).firstMatch.tap()
        waitForScreen(app, "screen.ideas")
        app.buttons["ideas.add"].tap()
        XCTAssertTrue(app.buttons["idea.save"].waitForExistence(timeout: 10))
        app.textFields["idea.note"].tap()
        app.textFields["idea.note"].typeText("Trail daypack")
        app.textFields["idea.price"].tap()
        app.textFields["idea.price"].typeText("45.00")
        app.buttons["idea.save"].tap()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Trail daypack")
            ).firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "$45.00")
            ).firstMatch.exists
        )

        // 3. Create occasion "Nova quiz" with a 50 budget, Nova attached.
        app.tabBars.buttons["Occasions"].tap()
        app.buttons["occasions.add"].tap()
        XCTAssertTrue(app.buttons["occasion.save"].waitForExistence(timeout: 10))
        app.textFields["occasion.name"].tap()
        app.textFields["occasion.name"].typeText("Nova quiz")
        app.textFields["occasion.budget"].tap()
        app.textFields["occasion.budget"].typeText("50.00")
        let novaToggle = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova")
        ).firstMatch
        XCTAssertTrue(novaToggle.waitForExistence(timeout: 10))
        novaToggle.tap()
        app.buttons["occasion.save"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Nova quiz")
            ).firstMatch.waitForExistence(timeout: 10)
        )

        // 4. Open the board, choose the idea, walk the state machine.
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova quiz")
        ).firstMatch.tap()
        waitForScreen(app, "screen.board")
        let chooseButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "board.choose")
        ).firstMatch
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 10))
        chooseButton.tap()
        // The chooser row carries the repeat-check + budget comparison
        // in its merged button label: exactly one idea for Nova.
        let pickButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "choose.pick")
        ).firstMatch
        XCTAssertTrue(pickButton.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Within budget")
            ).firstMatch.exists
        )
        pickButton.tap()

        // idea → chosen happened via the chooser; now chosen → bought →
        // wrapped → given: tap → Confirm for each legal step.
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
        waitForScreen(app, "screen.ledger")
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
