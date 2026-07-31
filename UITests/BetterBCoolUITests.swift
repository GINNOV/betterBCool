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

    func testSensorTagTemperatureAppearsAsRoomTemperatureSource() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sensortag-preview"]
        app.launch()

        let sensorTemperature = app.staticTexts["dashboard.sensorTagTemperature"]
        XCTAssertTrue(
            sensorTemperature.waitForExistence(timeout: 5),
            "The SensorTag temperature label did not appear"
        )
        XCTAssertEqual(sensorTemperature.label, "SensorTag temperature")
        XCTAssertEqual(sensorTemperature.value as? String, "23.4 degrees Celsius")
        XCTAssertTrue(app.staticTexts["SensorTag 23.4°"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "SensorTag temperature on climate dashboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPowerButtonChangesState() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let powerButton = app.buttons["dashboard.powerButton"]
        XCTAssertTrue(powerButton.waitForExistence(timeout: 5), "The power button did not appear")
        XCTAssertEqual(powerButton.label, "Turn air conditioner off")

        powerButton.tap()

        let changedLabel = NSPredicate(format: "label == %@", "Turn air conditioner on")
        expectation(for: changedLabel, evaluatedWith: powerButton)
        waitForExpectations(timeout: 5)
    }

    func testHalfDegreeTemperatureChangeHolds() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let increaseTemperature = app.buttons["Increase temperature"]
        XCTAssertTrue(increaseTemperature.waitForExistence(timeout: 5))
        increaseTemperature.tap()

        let halfDegreeSetpoint = app.staticTexts["25.5"]
        XCTAssertTrue(halfDegreeSetpoint.waitForExistence(timeout: 5), "The setpoint did not move by half a degree")

        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(halfDegreeSetpoint.exists, "The half-degree setpoint snapped back")
    }

    func testComfortSwingControlChangesState() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let verticalSwing = app.buttons["dashboard.verticalSwingButton"]
        XCTAssertTrue(verticalSwing.waitForExistence(timeout: 5))
        for _ in 0..<6 where !verticalSwing.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(verticalSwing.isHittable)
        XCTAssertEqual(verticalSwing.value as? String, "Off")
        verticalSwing.tap()

        let enabledState = NSPredicate(format: "value == %@", "On")
        expectation(for: enabledState, evaluatedWith: verticalSwing)
        waitForExpectations(timeout: 5)
    }

    func testLaunchDoesNotReplayAnAlreadyStartedPowerOnSchedule() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-power-off",
            "-ui-testing-with-active-power-on-schedule",
        ]
        app.launch()

        let powerButton = app.buttons["dashboard.powerButton"]
        XCTAssertTrue(powerButton.waitForExistence(timeout: 5))
        XCTAssertEqual(powerButton.label, "Turn air conditioner on")

        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(
            powerButton.label,
            "Turn air conditioner on",
            "Launching the app replayed an earlier schedule step and powered on the unit"
        )
    }

    func testUnitActivityCanBeCleared() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let increaseTemperature = app.buttons["Increase temperature"]
        XCTAssertTrue(increaseTemperature.waitForExistence(timeout: 5))
        increaseTemperature.tap()

        let clearButton = app.buttons["dashboard.clearActivityButton"]
        for _ in 0..<8 where !clearButton.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(clearButton.isHittable)
        XCTAssertTrue(app.staticTexts["Set to 25.5°"].waitForExistence(timeout: 5))
        let populatedLog = XCTAttachment(screenshot: app.screenshot())
        populatedLog.name = "Populated unit activity log"
        populatedLog.lifetime = .keepAlways
        add(populatedLog)

        clearButton.tap()

        XCTAssertTrue(app.staticTexts["Unit changes will appear here."].waitForExistence(timeout: 5))
        XCTAssertFalse(clearButton.isEnabled)
    }
}
