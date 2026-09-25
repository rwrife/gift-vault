import XCTest

final class GiftVaultLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesIntoWorkspace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // People tab is the default landing screen (NavigationStack
        // identifier matched by identifier across element types — the
        // List/Group container's element type is not guaranteed).
        let peopleScreen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "screen.people"))
            .firstMatch
        XCTAssertTrue(peopleScreen.waitForExistence(timeout: 10))
        // The fixture vault seeds five people including Ava Chen. List
        // rows are NavigationLinks (button elements); label children may
        // be merged, so match the row as a button by label.
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Ava Chen")
            ).firstMatch.waitForExistence(timeout: 10)
        )
    }
}
