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

    func testSettingsDoneDismissesSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let settingsButton = app.buttons["dashboard.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let doneButton = app.buttons["settings.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        XCTAssertTrue(doneButton.isEnabled)
        doneButton.tap()

        XCTAssertTrue(
            app.buttons["dashboard.settingsButton"].waitForExistence(timeout: 5),
            "The dashboard did not return after closing Settings"
        )
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    func testScheduleStepDoneReturnsToScheduleEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let schedulesButton = app.buttons["dashboard.schedulesButton"]
        XCTAssertTrue(schedulesButton.waitForExistence(timeout: 5))
        schedulesButton.tap()

        let addRoutineButton = app.buttons["Add routine"]
        XCTAssertTrue(addRoutineButton.waitForExistence(timeout: 5))
        addRoutineButton.tap()

        let addStepButton = app.buttons["Add a step"]
        XCTAssertTrue(addStepButton.waitForExistence(timeout: 5))
        addStepButton.tap()

        let doneButton = app.buttons["schedule.stepDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        XCTAssertTrue(addStepButton.waitForExistence(timeout: 5))
        XCTAssertFalse(doneButton.exists)
    }

    func testAppleWatchWristTemperatureAppearsOnDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-wrist-temperature-preview"]
        app.launch()

        let wristTemperature = app.staticTexts["dashboard.wristTemperature"]
        XCTAssertTrue(
            wristTemperature.waitForExistence(timeout: 5),
            "The Apple Watch wrist temperature label did not appear"
        )
        XCTAssertEqual(wristTemperature.label, "Apple Watch wrist temperature")
        XCTAssertEqual(wristTemperature.value as? String, "36.2 degrees Celsius")
        XCTAssertTrue(
            app.staticTexts["Wrist temperature"].waitForExistence(timeout: 5),
            "The wrist-temperature detail card did not appear"
        )
        let wristCard = app.otherElements["dashboard.bodyTemperatureCard"]
        let activityTitle = app.staticTexts["Activity"]
        for _ in 0..<8 where !activityTitle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(wristCard.exists)
        XCTAssertTrue(activityTitle.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Apple Watch wrist temperature on climate dashboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAppleWatchSettingsOnlyShowAutomationControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["dashboard.settingsButton"].tap()

        XCTAssertTrue(app.switches["Cool based on Apple Watch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Trigger above baseline"].exists)
        XCTAssertFalse(app.buttons["settings.healthAuthorizationButton"].exists)
        XCTAssertFalse(app.staticTexts["Latest wrist temperature"].exists)
        XCTAssertFalse(app.buttons["Refresh temperature"].exists)
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

    func testPowerOffDisablesClimateSettingsButKeepsSchedulesAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-power-off"]
        app.launch()

        let powerButton = app.buttons["dashboard.powerButton"]
        XCTAssertTrue(powerButton.waitForExistence(timeout: 5))
        XCTAssertTrue(powerButton.isEnabled, "The power control must remain available to turn the unit back on")
        XCTAssertEqual(powerButton.label, "Turn air conditioner on")

        let increaseTemperature = app.buttons["Increase temperature"]
        XCTAssertTrue(increaseTemperature.waitForExistence(timeout: 5))
        XCTAssertFalse(increaseTemperature.isEnabled)

        let coolMode = app.buttons["Cool"]
        XCTAssertTrue(coolMode.waitForExistence(timeout: 5))
        XCTAssertFalse(coolMode.isEnabled)

        let verticalSwing = app.buttons["dashboard.verticalSwingButton"]
        XCTAssertTrue(verticalSwing.waitForExistence(timeout: 5))
        XCTAssertFalse(verticalSwing.isEnabled)

        let schedulesButton = app.buttons["dashboard.schedulesButton"]
        XCTAssertTrue(schedulesButton.isEnabled, "Schedules must remain available while the unit is off")
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

    func testEcoAndSleepControlsChangeState() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        for identifier in ["dashboard.ecoButton", "dashboard.sleepButton"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            for _ in 0..<6 where !button.isHittable {
                app.swipeUp()
            }

            XCTAssertTrue(button.isHittable)
            XCTAssertEqual(button.value as? String, "Off")
            button.tap()

            let enabledState = NSPredicate(format: "value == %@", "On")
            expectation(for: enabledState, evaluatedWith: button)
            waitForExpectations(timeout: 5)
        }
    }

    func testDryModeDisablesIncompatibleComfortControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let dryMode = app.buttons["Dry"]
        XCTAssertTrue(dryMode.waitForExistence(timeout: 5))
        dryMode.tap()

        for identifier in ["dashboard.ecoButton", "dashboard.sleepButton"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertFalse(button.isEnabled)
            XCTAssertEqual(button.value as? String, "Unavailable")
        }

        XCTAssertTrue(app.staticTexts["Managed automatically in Dry mode"].exists)
        for fanSpeed in ["Auto", "Quiet", "Low", "Medium", "High", "Turbo"] {
            let matchingButtons = app.buttons.matching(NSPredicate(format: "label == %@", fanSpeed))
            let fanButton = matchingButtons.element(boundBy: matchingButtons.count - 1)
            XCTAssertTrue(fanButton.exists, "Missing \(fanSpeed) fan-speed button")
            XCTAssertFalse(fanButton.isEnabled, "\(fanSpeed) should be disabled in Dry mode")
        }
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
