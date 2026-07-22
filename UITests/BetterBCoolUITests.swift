// SPDX-License-Identifier: Apache-2.0

import XCTest

final class BetterBCoolUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsButtonOpensSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let settingsButton = app.buttons["dashboard.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "The settings button did not appear")
        XCTAssertTrue(settingsButton.isHittable, "The settings button is not tappable")

        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open")
        XCTAssertTrue(
            app.buttons["settings.signInButton"].waitForExistence(timeout: 5),
            "The Bosch sign-in control did not appear"
        )
    }
}
