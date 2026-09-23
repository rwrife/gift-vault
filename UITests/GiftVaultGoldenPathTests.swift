import XCTest

/// Issue #4 golden path: add person → add idea → create occasion →
/// choose idea → mark given → ledger shows the entry. Launches against
/// the fixture vault (`-ui-testing`), which never contains "Nova" or
/// "Trail daypack".
///
/// Query strategy per row type (SwiftUI → XCUITest):
/// - NavigationLink rows: label Text surfaces as staticText; rows also
///   exist as cells for positional taps.
/// - Button rows (idea list, chooser): the label content MERGES into
///   the single button element — locate by the button's own
///   accessibilityIdentifier or by merged label CONTAINS, never by a
///   child staticText.
/// - Plain row content (board rows, ledger rows): Text nodes surface as
///   staticTexts; scope queries inside the screen element to avoid
///   cross-tab false positives.
final class GiftVaultGoldenPathTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func screen(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", id))
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "screen \(id) not found")
        return element
    }

    @MainActor
    func testGoldenPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        screen(app, "screen.people")

        // 1. Add person "Nova".
        let peopleTab = app.tabBars.buttons["People"]
        XCTAssertTrue(peopleTab.waitForExistence(timeout: 10))
        peopleTab.tap()
        app.buttons["people.add"].tap()
        XCTAssertTrue(app.buttons["person.save"].waitForExistence(timeout: 10))
        app.textFields["person.name"].tap()
        app.textFields["person.name"].typeText("Nova")
        app.buttons["person.save"].tap()
        // NavigationLink row: the name surfaces as staticText.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Nova")
            ).firstMatch.waitForExistence(timeout: 10)
        )

        // 2. Add an idea with a price hint (on Ava Chen's wishlist, a
        // fixture person whose idea list we can re-open).
        let avaRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Ava Chen")
        ).firstMatch
        XCTAssertTrue(avaRow.waitForExistence(timeout: 10))
        avaRow.tap()
        screen(app, "screen.ideas")
        app.buttons["ideas.add"].tap()
        XCTAssertTrue(app.buttons["idea.save"].waitForExistence(timeout: 10))
        app.textFields["idea.note"].tap()
        app.textFields["idea.note"].typeText("Trail daypack")
        app.textFields["idea.price"].tap()
        app.textFields["idea.price"].typeText("45.00")
        app.buttons["idea.save"].tap()
        // Idea rows are Buttons: match the merged button label.
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
        app.navigationBars.buttons.firstMatch.tap() // back to People list

        // 3. Create occasion "Nova quiz", budget 50, attach Ava Chen.
        app.tabBars.buttons["Occasions"].tap()
        app.buttons["occasions.add"].tap()
        XCTAssertTrue(app.buttons["occasion.save"].waitForExistence(timeout: 10))
        app.textFields["occasion.name"].tap()
        app.textFields["occasion.name"].typeText("Nova quiz")
        app.textFields["occasion.budget"].tap()
        app.textFields["occasion.budget"].typeText("50.00")
        let avaToggle = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "Ava Chen")
        ).firstMatch
        XCTAssertTrue(avaToggle.waitForExistence(timeout: 10))
        avaToggle.tap()
        app.buttons["occasion.save"].tap()

        // 4. Open the NEW occasion's board deterministically by position:
        // dated occasions sort first, undated by name last — "Nova quiz"
        // is the final row.
        screen(app, "screen.occasions")
        let occasionRows = app.descendants(matching: .cell)
        XCTAssertTrue(occasionRows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(occasionRows.count, 2)
        occasionRows.element(boundBy: occasionRows.count - 1).tap()
        screen(app, "screen.board")

        // 5. Choose the trail daypack idea (repeat-check + budget state
        // are shown in the chooser), then walk the state machine.
        let chooseButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "board.choose")
        ).firstMatch
        if !chooseButton.waitForExistence(timeout: 10) {
            // One-shot diagnostic: dump the live hierarchy (identifiers,
            // labels, frames) so the next fix is grounded in fact.
            print("DX(board) board.count=\(app.descendants(matching: .cell).count)")
            print("DX(board) buttons=\(app.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" })")
            print("DX(board) statics=\(app.staticTexts.allElementsBoundByIndex.map { $0.label })")
            print("DX(tree)\n\(app.debugDescription)")
            XCTFail("board choose button never appeared")
            return
        }
        chooseButton.tap()
        let daypackPick = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Trail daypack")
        ).firstMatch
        XCTAssertTrue(daypackPick.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Within budget")
            ).firstMatch.exists
        )
        daypackPick.tap()

        // idea → chosen happened via the chooser; advance the remaining
        // three legal steps: chosen → bought → wrapped → given.
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
        // Terminal state: the seam now offers no control on the board.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Gift given")
            ).firstMatch.waitForExistence(timeout: 10)
        )

        // 6. The given transition wrote the implied ledger row. Scope to
        // the ledger screen so hidden tab content can't satisfy this.
        app.tabBars.buttons["Ledger"].tap()
        let ledgerScreen = screen(app, "screen.ledger")
        XCTAssertTrue(
            ledgerScreen.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Given Ava Chen")
            ).firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            ledgerScreen.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Trail daypack")
            ).firstMatch.waitForExistence(timeout: 10)
        )
    }
}
