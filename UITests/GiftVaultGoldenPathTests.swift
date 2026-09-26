import XCTest

/// Issue #4 golden path: add person → add idea → create occasion →
/// choose idea → mark given → ledger shows the entry. Launches against
/// the fixture vault (`-ui-testing`), which never contains "Nova" or
/// "Trail daypack".
///
/// Query grammar (CI run 35910710111: the new occasion's board rendered
/// ZERO slot rows — the attached toggle state never reached the model):
/// every step waits for HITTABLE state (not mere existence), the attach
/// toggle's value is printed after tapping, and any failed wait dumps
/// the live accessibility tree so the next fix is grounded in fact.
/// In-list controls merge their label content into one element, so they
/// are matched by merged label; toolbar/sheet controls keep their own
/// accessibilityIdentifiers. Navigation happens by visible row label,
/// never by positional cell taps.
final class GiftVaultGoldenPathTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func hittable(_ app: XCUIApplication, _ element: XCUIElement,
                          _ what: String, timeout: TimeInterval = 10) {
        // `waitForHittable(timeout:)` is private XCUITest API and does not
        // compile against the public SDK; poll the public `isHittable`
        // property until the deadline instead.
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < deadline {
            _ = element.waitForExistence(timeout: 0.25)
        }
        if !element.isHittable {
            print("DX(hittable) FAILED for \(what)")
            print("DX(tree)\n\(app.debugDescription)")
        }
        XCTAssertTrue(element.isHittable, "\(what) never became hittable")
    }

    /// CI run 35983045785: the newly-added person's attach toggle renders
    /// at the very bottom of the occasion sheet, past the visible viewport,
    /// so it exists but is never hittable. Scroll the sheet (up) until the
    /// element becomes hittable, bounded, then assert.
    @MainActor
    private func hittableAfterScrolling(_ app: XCUIApplication, _ element: XCUIElement,
                                        _ what: String, in scrollable: XCUIElement,
                                        maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            _ = element.waitForExistence(timeout: 2)
            if element.isHittable { break }
            scrollable.swipeUp()
            swipes += 1
        }
        hittable(app, element, what)
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
        hittable(app, app.buttons["people.add"], "people.add toolbar button")
        app.buttons["people.add"].tap()
        hittable(app, app.buttons["person.save"], "person sheet")
        app.textFields["person.name"].tap()
        app.textFields["person.name"].typeText("Nova")
        app.buttons["person.save"].tap()
        let novaRow = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Nova")
        ).firstMatch
        hittable(app, novaRow, "Nova people row")

        // 2. Add an idea with a price hint for Nova.
        novaRow.tap()
        hittable(app, app.buttons["ideas.add"], "ideas.add toolbar button")
        app.buttons["ideas.add"].tap()
        hittable(app, app.buttons["idea.save"], "idea sheet")
        app.textFields["idea.note"].tap()
        app.textFields["idea.note"].typeText("Trail daypack")
        app.textFields["idea.price"].tap()
        app.textFields["idea.price"].typeText("45.00")
        app.buttons["idea.save"].tap()
        // Idea rows are Buttons; their merged label carries note + price.
        let daypackRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Trail daypack")
        ).firstMatch
        hittable(app, daypackRow, "Trail daypack idea row")

        // 3. Create occasion "Nova quiz", budget 50, attach Nova.
        hittable(app, app.tabBars.buttons["Occasions"], "Occasions tab")
        app.tabBars.buttons["Occasions"].tap()
        hittable(app, app.buttons["occasions.add"], "occasions.add toolbar button")
        app.buttons["occasions.add"].tap()
        hittable(app, app.buttons["occasion.save"], "occasion sheet")
        // Attach people BEFORE any text editing. CI run 35986475990: the
        // decimal-pad keyboard has no return key to dismiss it, and the
        // open keyboard (frame y=451..667) covered the Nova toggle at
        // y=614 and consumed every swipeUp on the sheet, so the toggle
        // existed but never became hittable. With no keyboard open the
        // form renders/swipes normally; the toolbar Save button stays
        // hittable with the keyboard up (proven by the person/idea
        // sheets earlier in this test).
        let novaToggle = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova")
        ).firstMatch
        hittableAfterScrolling(app, novaToggle, "Nova attach toggle",
                               in: app.collectionViews["sheet.occasion"])
        // Run 36080808603: a synthesized tap on the merged row (center on
        // the label text) left the value at 0 and the saved occasion had
        // zero board slots — the binding never flipped. Tap the actual
        // switch control nested in the row, then assert the flipped
        // value reached the accessibility tree before saving.
        let novaSwitch = novaToggle.switches.firstMatch
        _ = novaSwitch.waitForExistence(timeout: 2)
        (novaSwitch.exists ? novaSwitch : novaToggle).tap()
        // Poll the switch value (string "1" when on) until the flipped
        // state reaches the accessibility tree, bounded.
        var attached = false
        let flipDeadline = Date().addingTimeInterval(5)
        while !attached && Date() < flipDeadline {
            let probe = novaSwitch.exists ? novaSwitch : novaToggle
            attached = String(describing: probe.value).contains("1")
            if !attached { Thread.sleep(forTimeInterval: 0.25) }
        }
        if !attached {
            print("DX(switch)\n\(novaToggle.debugDescription)")
        }
        XCTAssertTrue(attached, "Nova attach toggle never reported ON")
        app.textFields["occasion.name"].tap()
        app.textFields["occasion.name"].typeText("Nova quiz")
        app.textFields["occasion.budget"].tap()
        app.textFields["occasion.budget"].typeText("50.00")
        app.buttons["occasion.save"].tap()

        // 4. Open the new occasion's board by its row label.
        let quizRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Nova quiz")
        ).firstMatch
        hittable(app, quizRow, "Nova quiz occasion row")
        quizRow.tap()

        // 5. Choose the trail daypack idea (repeat-check + budget state
        // are shown in the chooser), then walk the state machine.
        let chooseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Choose idea")
        ).firstMatch
        hittable(app, chooseButton, "board choose button")
        chooseButton.tap()
        let daypackPick = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Trail daypack")
        ).firstMatch
        hittable(app, daypackPick, "chooser daypack row")
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
            hittable(app, advance, "advance button \(step)")
            advance.tap()
            let confirm = app.buttons["Confirm"]
            hittable(app, confirm, "confirm button for \(step)")
            confirm.tap()
        }
        // Terminal state: the seam offers no further control.
        let givenLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Gift given")
        ).firstMatch
        hittable(app, givenLabel, "Gift given terminal marker")

        // 6. The given transition wrote the implied ledger row.
        hittable(app, app.tabBars.buttons["Ledger"], "Ledger tab")
        app.tabBars.buttons["Ledger"].tap()
        hittable(app, app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Given Nova")
        ).firstMatch, "Given Nova ledger row")
        hittable(app, app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Trail daypack")
        ).firstMatch, "chosen idea description in ledger row")
    }

    /// Issue #5: Dynamic Type — at the largest accessibility size the key
    /// controls of each tab remain reachable (no clipped/off-screen
    /// essentials), which is the layout-level half of the accessibility
    /// pass. Content-size category is injected via the standard simulator
    /// user-default launch argument.
    @MainActor
    func testLargeDynamicTypeKeepsKeyControlsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-ax-max",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let avaRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Ava Chen")
        ).firstMatch
        hittableAfterScrolling(app, avaRow, "Ava Chen people row at AX size",
                               in: app.collectionViews.firstMatch)

        hittable(app, app.buttons["people.add"], "people.add at AX size")

        let occasionsTab = app.tabBars.buttons["Occasions"]
        hittable(app, occasionsTab, "Occasions tab at AX size")
        occasionsTab.tap()
        hittable(app, app.buttons["occasions.add"], "occasions.add at AX size")

        let ledgerTab = app.tabBars.buttons["Ledger"]
        hittable(app, ledgerTab, "Ledger tab at AX size")
        ledgerTab.tap()
        let screen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "screen.ledger"))
            .firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10), "ledger screen missing at AX size")
    }

    /// Issue #5 acceptance: with notifications denied, occasion dates (and
    /// their reminders) degrade gracefully — the reminder affordance is
    /// still shown and saving a dated occasion still works. The app uses a
    /// fake denied permission center under `-ui-testing-notifications-denied`
    /// so no system alert interferes with the journey.
    @MainActor
    func testNotificationDeniedPathKeepsAppUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-notifications-denied"]
        app.launch()

        let occasionsTab = app.tabBars.buttons["Occasions"]
        XCTAssertTrue(occasionsTab.waitForExistence(timeout: 10))
        occasionsTab.tap()
        hittable(app, app.buttons["occasions.add"], "occasions.add")
        app.buttons["occasions.add"].tap()
        hittable(app, app.buttons["occasion.save"], "occasion sheet")

        // Attach an existing person BEFORE any text editing (keyboard
        // hygiene proven by the golden path), then use the date toggle —
        // the first "occasion-date use", where permission is requested
        // lazily and here comes back denied.
        let avaToggle = app.switches.matching(
            NSPredicate(format: "label CONTAINS %@", "Ava Chen")
        ).firstMatch
        hittableAfterScrolling(app, avaToggle, "Ava attach toggle",
                               in: app.collectionViews["sheet.occasion"])
        let avaSwitch = avaToggle.switches.firstMatch
        _ = avaSwitch.waitForExistence(timeout: 2)
        (avaSwitch.exists ? avaSwitch : avaToggle).tap()
        var attached = false
        let flipDeadline = Date().addingTimeInterval(5)
        while !attached && Date() < flipDeadline {
            let probe = avaSwitch.exists ? avaSwitch : avaToggle
            attached = String(describing: probe.value).contains("1")
            if !attached { Thread.sleep(forTimeInterval: 0.25) }
        }
        XCTAssertTrue(attached, "Ava attach toggle never reported ON")

        let hasDateToggle = app.switches.matching(
            NSPredicate(format: "identifier == %@ OR label CONTAINS %@", "occasion.hasDate", "Has a date")
        ).firstMatch
        hittable(app, hasDateToggle, "occasion.hasDate")
        let hasDateSwitch = hasDateToggle.switches.firstMatch
        _ = hasDateSwitch.waitForExistence(timeout: 2)
        (hasDateSwitch.exists ? hasDateSwitch : hasDateToggle).tap()
        var hasDateEnabled = false
        let dateFlipDeadline = Date().addingTimeInterval(5)
        while !hasDateEnabled && Date() < dateFlipDeadline {
            let probe = hasDateSwitch.exists ? hasDateSwitch : hasDateToggle
            hasDateEnabled = String(describing: probe.value).contains("1")
            if !hasDateEnabled { Thread.sleep(forTimeInterval: 0.25) }
        }
        XCTAssertTrue(hasDateEnabled, "Has a date toggle never reported ON")

        // The reminder note appears (documentation of the disabled state),
        // and the app keeps working despite the denied permission.
        let reminderNote = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "occasion.reminderNote"))
            .firstMatch
        XCTAssertTrue(reminderNote.waitForExistence(timeout: 5),
                      "reminder note missing after enabling the date")

        app.textFields["occasion.name"].tap()
        app.textFields["occasion.name"].typeText("Denied quiz")
        app.textFields["occasion.budget"].tap()
        app.textFields["occasion.budget"].typeText("25.00")
        app.buttons["occasion.save"].tap()

        let quizRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Denied quiz")
        ).firstMatch
        hittable(app, quizRow, "saved dated occasion row with notifications denied")
    }

    /// Issue #6: the Settings → Backup flow is reachable and every
    /// export/restore affordance renders (share-sheet and file-picker
    /// presentation themselves are system UI exercised manually; the
    /// bundle/CSV logic is covered by the package store tests).
    @MainActor
    func testBackupScreenExposesExportAndRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab missing")
        settingsTab.tap()

        let backupRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Backup")
        ).firstMatch
        XCTAssertTrue(backupRow.waitForExistence(timeout: 10), "Backup row missing")
        backupRow.tap()

        for id in [
            "backup.exportBundle",
            "backup.exportIdeasCSV",
            "backup.exportOccasionsCSV",
            "backup.exportLedgerCSV",
            "backup.restore",
        ] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(id) missing")
            XCTAssertTrue(button.isHittable, "\(id) not hittable")
        }
    }
}
