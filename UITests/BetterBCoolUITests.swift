// SPDX-License-Identifier: Apache-2.0

import XCTest

final class BetterBCoolUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testItalianSystemLanguageUsesItalianThroughoutInterface() {
        assertInterfaceLanguage("it-CH", region: "it_CH", settingsTitle: "Impostazioni", powerLabel: "Spegni il climatizzatore")
    }

    func testUnsupportedLanguageFallsBackToEnglishWithItalianSecondary() {
        assertInterfaceLanguage("fr-FR", region: "it_IT", settingsTitle: "Settings", powerLabel: "Turn air conditioner off")
    }

    func testEnglishSystemLanguageUsesEnglish() {
        assertInterfaceLanguage("en-GB", region: "en_GB", settingsTitle: "Settings", powerLabel: "Turn air conditioner off")
    }

    private func assertInterfaceLanguage(_ language: String, region: String, settingsTitle: String, powerLabel: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language),it)", "-AppleLocale", region]
        app.launch()
        let power = app.buttons["dashboard.powerButton"]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        XCTAssertEqual(power.label, powerLabel)
        let subtitle = language.hasPrefix("it") ? "Stato e controlli di oscillazione" : "Status and swing controls"
        let comfortSubtitle = app.staticTexts[subtitle]
        for _ in 0..<6 where !comfortSubtitle.exists { app.swipeUp() }
        XCTAssertTrue(comfortSubtitle.exists)
        app.buttons["dashboard.settingsButton"].tap()
        XCTAssertTrue(app.navigationBars[settingsTitle].waitForExistence(timeout: 5))
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

    func testTemperatureCardHasNoCoolingOrOffStatusBadge() {
        for language in ["en", "it"] {
            for poweredOff in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))"]
                if poweredOff { app.launchArguments.append("-ui-testing-power-off") }
                app.launch()
                let card = app.otherElements["dashboard.temperatureCard"]
                XCTAssertTrue(card.waitForExistence(timeout: 5))
                for label in ["COOLING", "OFF", "RAFFREDDAMENTO", "SPENTO"] {
                    XCTAssertFalse(card.staticTexts[label].exists)
                }
                XCTAssertTrue(app.buttons["dashboard.powerButton"].isEnabled)
                XCTAssertTrue(app.buttons["dashboard.schedulesButton"].exists)
                captureStatusDashboard(app, name: "Temperature card \(language), off=\(poweredOff)")
                app.terminate()
            }
        }
    }

    private func captureStatusDashboard(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

    func testMultiStepScheduleCanEnterReorderMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let schedulesButton = app.buttons["dashboard.schedulesButton"]
        XCTAssertTrue(schedulesButton.waitForExistence(timeout: 5))
        schedulesButton.tap()

        let templateButton = app.buttons["Start with Night comfort"]
        XCTAssertTrue(templateButton.waitForExistence(timeout: 5))
        templateButton.tap()

        let reorderButton = app.buttons["schedule.reorderStepsButton"]
        XCTAssertTrue(reorderButton.waitForExistence(timeout: 5))
        XCTAssertEqual(reorderButton.label, "Reorder")

        reorderButton.tap()

        XCTAssertEqual(reorderButton.label, "Done")
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

        let verticalSwing = revealComfortControl("dashboard.verticalSwingButton", in: app)
        XCTAssertTrue(verticalSwing.waitForExistence(timeout: 5))
        XCTAssertFalse(verticalSwing.isEnabled)

        let schedulesButton = app.buttons["dashboard.schedulesButton"]
        XCTAssertTrue(schedulesButton.isEnabled, "Schedules must remain available while the unit is off")
    }

    func testComfortLabelsAndStatesRemainAccessibleAtLargestTextSize() {
        verifyComfortControls(language: "en", largestText: false)
        verifyComfortControls(language: "it", largestText: false)
        verifyComfortControls(language: "it", largestText: true)
    }

    private func verifyComfortControls(language: String, largestText: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))"]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let identifiers = ["dashboard.ecoButton", "dashboard.sleepButton", "dashboard.verticalSwingButton", "dashboard.horizontalSwingButton"]
        for identifier in identifiers {
            let control = revealComfortControl(identifier, in: app)
            XCTAssertTrue(control.isHittable)
            XCTAssertFalse(control.label.contains("..."))
            XCTAssertFalse(control.label.contains("…"))
            let originalState = control.value as? String
            let states = language == "it" ? ["Acceso", "Spento"] : ["On", "Off"]
            XCTAssertTrue(states.contains(originalState ?? ""))
            control.tap()
            let changed = NSPredicate(format: "value != %@", originalState ?? "")
            expectation(for: changed, evaluatedWith: control)
            waitForExpectations(timeout: 5)
            captureComfortDashboard(app, name: "Comfort \(language), largest=\(largestText), \(identifier)")
        }
        app.terminate()
    }

    private func revealComfortControl(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let control = app.buttons[identifier]
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<12 {
            if control.exists && (control.isHittable || !control.isEnabled) { return control }
            scrollView.swipeUp(velocity: .slow)
        }
        return control
    }

    private func captureComfortDashboard(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

        let verticalSwing = revealComfortControl("dashboard.verticalSwingButton", in: app)
        XCTAssertTrue(verticalSwing.waitForExistence(timeout: 5))
        for _ in 0..<6 where !verticalSwing.isHittable {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
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
            let button = revealComfortControl(identifier, in: app)
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            for _ in 0..<6 where !button.isHittable {
                app.scrollViews.firstMatch.swipeUp(velocity: .slow)
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

        XCTAssertTrue(app.staticTexts["Managed automatically in Dry mode"].exists)
        for fanSpeed in ["Auto", "Quiet", "Low", "Medium", "High", "Turbo"] {
            let matchingButtons = app.buttons.matching(NSPredicate(format: "label == %@", fanSpeed))
            let fanButton = matchingButtons.element(boundBy: matchingButtons.count - 1)
            XCTAssertTrue(fanButton.exists, "Missing \(fanSpeed) fan-speed button")
            XCTAssertFalse(fanButton.isEnabled, "\(fanSpeed) should be disabled in Dry mode")
        }

        for identifier in ["dashboard.ecoButton", "dashboard.sleepButton"] {
            let button = revealComfortControl(identifier, in: app)
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertFalse(button.isEnabled)
            XCTAssertEqual(button.value as? String, "Unavailable")
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

    func testIconOnlyModesKeepLabelsSelectionAndSwitching() {
        for language in ["en", "it"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))"]
            app.launch()
            let cool = app.buttons["dashboard.mode.cool"]
            XCTAssertTrue(cool.waitForExistence(timeout: 5))
            XCTAssertEqual(cool.label, language == "it" ? "Raffredda" : "Cool")
            XCTAssertTrue(cool.isSelected)
            let heat = app.buttons["dashboard.mode.heat"]
            let heatLabel = language == "it" ? "Riscalda" : "Heat"
            XCTAssertEqual(heat.label, heatLabel)
            heat.tap()
            let selected = NSPredicate(format: "selected == true")
            expectation(for: selected, evaluatedWith: heat)
            waitForExpectations(timeout: 5)
            XCTAssertFalse(cool.isSelected)
            XCTAssertEqual(app.staticTexts["dashboard.modeSummary"].label, language == "it" ? "Riscaldamento" : "Heat")
            XCTAssertFalse(heat.staticTexts[heatLabel].exists)
            captureModeDashboard(app, name: "Text-only summary and icon-only selector \(language)")
            app.terminate()
        }
    }

    func testAllModeSummariesFitInBothLanguagesAtLargestTextSize() {
        for language in ["en", "it"] {
            for largestText in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))"]
                if largestText {
                    app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
                }
                app.launch()
                let modes = ["auto", "cool", "dry", "fan", "heat"]
                let names = language == "it"
                    ? ["Automatico", "Raffreddamento", "Deumidificazione", "Ventilazione", "Riscaldamento"]
                    : ["Auto", "Cool", "Dry", "Fan", "Heat"]
                for (mode, name) in zip(modes, names) {
                    let button = app.buttons["dashboard.mode.\(mode)"]
                    for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
                    XCTAssertTrue(button.isHittable)
                    button.tap()
                    let selected = NSPredicate(format: "selected == true")
                    expectation(for: selected, evaluatedWith: button)
                    waitForExpectations(timeout: 5)
                    let summary = app.staticTexts["dashboard.modeSummary"]
                    for _ in 0..<8 where !summary.isHittable { app.scrollViews.firstMatch.swipeDown(velocity: .fast) }
                    XCTAssertTrue(summary.waitForExistence(timeout: 5))
                    XCTAssertEqual(summary.label, name)
                    XCTAssertTrue(summary.isHittable)
                    let card = app.otherElements["dashboard.temperatureCard"]
                    XCTAssertTrue(card.frame.contains(summary.frame), "Mode summary must stay inside the card")
                    XCTAssertFalse(summary.frame.intersects(app.buttons["dashboard.increaseTemperature"].frame))
                    XCTAssertFalse(summary.frame.intersects(app.buttons["dashboard.decreaseTemperature"].frame))
                    let decrease = app.buttons["dashboard.decreaseTemperature"]
                    let increase = app.buttons["dashboard.increaseTemperature"]
                    XCTAssertLessThan(decrease.frame.maxX, summary.frame.minX)
                    XCTAssertLessThan(summary.frame.maxX, increase.frame.minX)
                    XCTAssertEqual(summary.frame.midY, decrease.frame.midY, accuracy: 2)
                    XCTAssertEqual(summary.frame.midY, increase.frame.midY, accuracy: 2)
                    for control in [decrease, increase] {
                        XCTAssertGreaterThanOrEqual(control.frame.width, 44)
                        XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                        XCTAssertTrue(card.frame.contains(control.frame))
                    }
                    captureModeDashboard(app, name: "Mode \(mode), \(language), largest=\(largestText)")
                }
                app.terminate()
            }
        }
    }

    private func captureModeDashboard(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
