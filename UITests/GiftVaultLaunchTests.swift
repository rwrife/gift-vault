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
        // identifier — the pattern proven by the bootstrap launch smoke).
        let peopleScreen = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "screen.people"))
            .firstMatch
        XCTAssertTrue(peopleScreen.waitForExistence(timeout: 10))
        // The fixture vault seeds five people including Ava Chen.
        XCTAssertTrue(app.staticTexts["Ava Chen"].waitForExistence(timeout: 10))
    }
}
