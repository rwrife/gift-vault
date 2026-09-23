import XCTest

/// Issue #4 golden path: add person → add idea → create occasion →
/// choose idea → mark given → ledger shows the entry. Launches against
/// the fixture vault (`-ui-testing`), which never contains "Nova" or
/// "Trail daypack".
///
/// Query grammar (grounded in the CI AX-hierarchy dump, run 35910710111):
/// - SwiftUI List content MERGES cell controls into synthesized cell
///   elements whose accessibilityIdentifier is dropped; only the merged
///   LABEL survives. In-list controls are therefore matched by label.
/// - Toolbar items, sheet fields, and sheet buttons keep their own
///   accessibilityIdentifiers — match those by identifier.
/// - Every step waits for `waitForHittable` (not `exists`), so content
///   retained behind sheets/tabs/hidden stacks can never satisfy an
///   assertion or steal a tap.
/// - Navigation never happens by positional cell taps (a tap during a
///   push transition can land on the incoming screen); rows are tapped
///   by their visible label.
final class GiftVaultGoldenPathTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func hittable(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForHittable(timeout: timeout), "\(what) never became hittable")
    }

    @MainActor
    func testGoldenPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // 1. Add person "Nova".
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Ava Chen")
            ).firstMatch.waitForExistence(timeout: 10),
            "fixture vault did not seed"
        )
        hittable(app.buttons["people.add"], "people.add toolbar button")
        app.buttons["people.add"].tap()
        hittable(app.buttons["person.save"], "person sheet")
        app.textFields["person.name"].tap()
        app.textFields["person.name"].typeText("Nova")
        app.buttons["person.save"].tap()
        let novaRow = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Nova")
        ).firstMatch
        hittable(novaRow, "Nova people row")

        // 2. Add an idea with a price hint for Nova.
        novaRow.tap()
        hittable(app.buttons["ideas.add"], "ideas.add toolbar button")
        app.buttons["ideas.add"].tap()
        hittable(app.buttons["idea.save"], "idea sheet")
        app.textFields["idea.note"].tap()
        app.textFields["idea.note"].typeText("Trail daypack")
        app.textFields["idea.price"].tap()
        app.textFields["idea.price"].typeText("45.00")
        app.buttons["idea.save"].tap()
        // Idea rows are Buttons; their merged label carries note + price.
        let daypackRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Trail daypack")
        ).firstMatch
        hittable(daypackRow, "Trail daypack idea row")

        // 3. Create occasion "Nova quiz", budget 50, attach Nova.
        hittable(app.tabBars.buttons["Occasions"], "Occasions tab")
        app.tabBars.buttons["Occasions"].tap()
        hittable(app.buttons["occasions.add"], "occasions.add toolbar button")
        app.buttons["occasions.add"].tap()
        hittable(app.buttons["occasion.save"], "occasion sheet")
        app.textFields["occasion.name"].tap()
        app.textFields["occasion.name"].typeText("Nova quiz")
        app.textFields["occasion.budget"].tap()
        app.textFields["occasion.budget"].typeText("50.00")
        let novaToggle = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova")
        ).firstMatch
        hittable(novaToggle, "Nova attach toggle")
        novaToggle.tap()
        app.buttons["occasion.save"].tap()

        // 4. Open the new occasion's board by its row label.
        let quizRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova quiz")
        ).firstMatch
        hittable(quizRow, "Nova quiz occasion row")
        quizRow.tap()

        // 5. Choose the trail daypack idea (repeat-check + budget state
        // are shown in the chooser), then walk the state machine.
        let chooseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Choose idea")
        ).firstMatch
        hittable(chooseButton, "board choose button")
        chooseButton.tap()
        let daypackPick = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Trail daypack")
        ).firstMatch
        hittable(daypackPick, "chooser daypack row")
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Within budget")
            ).firstMatch.exists,
            "chooser did not surface the budget comparison"
        )
        daypackPick.tap()

        // idea → chosen happened via the chooser; advance the remaining
        // legal steps: chosen → bought → wrapped → given.
        for step in ["Mark bought", "Mark wrapped", "Mark given"] {
            let advance = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", step)
            ).firstMatch
            hittable(advance, "advance button \(step)")
            advance.tap()
            let confirm = app.buttons["Confirm"]
            hittable(confirm, "confirm button for \(step)")
            confirm.tap()
        }
        // Terminal state: the seam offers no further control.
        let givenLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Gift given")
        ).firstMatch
        hittable(givenLabel, "Gift given terminal marker")

        // 6. The given transition wrote the implied ledger row.
        hittable(app.tabBars.buttons["Ledger"], "Ledger tab")
        app.tabBars.buttons["Ledger"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Given Nova")
            ).firstMatch.waitForHittable(timeout: 10),
            "ledger has no Given Nova row"
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Trail daypack")
            ).firstMatch.waitForHittable(timeout: 10),
            "ledger row lost the chosen idea description"
        )
    }
}
