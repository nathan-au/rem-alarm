//
//  ArmAlarmUITests.swift
//  rem-alarmUITests
//

import XCTest

final class ArmAlarmUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Tap the first cycle and confirm we land on the armed screen.
    @MainActor
    func testArmingFirstCycleShowsConfirmation() throws {
        let app = XCUIApplication()
        app.launch()

        // Grant the AlarmKit permission prompt if it appears.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        addUIInterruptionMonitor(withDescription: "Alarm permission") { alert in
            for label in ["Allow", "OK", "Continue"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }

        let firstRow = app.buttons["cycleOption.1"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), "cycle list should render")
        firstRow.tap()

        // Interruption monitors only fire after the next interaction, so nudge
        // the permission alert directly.
        for label in ["Allow", "OK", "Continue"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) { button.tap(); break }
        }

        let confirmation = app.staticTexts["Alarm set for"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "armed screen should appear")

        let cancel = app.buttons["Cancel alarm"]
        XCTAssertTrue(cancel.exists, "armed screen should offer a cancel button")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "armed"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Back to the picker.
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Sleep now, wake at"].waitForExistence(timeout: 5),
                      "cancelling should return to the picker")
    }

    /// Changing the number of options has to change the length of the list.
    ///
    /// Settings persist across launches, so this normalises them through the
    /// reset button at both ends rather than assuming a starting value.
    @MainActor
    func testOptionCountControlsListLength() throws {
        let app = XCUIApplication()
        app.launch()

        resetSettings(in: app)

        XCTAssertTrue(app.buttons["cycleOption.10"].waitForExistence(timeout: 5),
                      "ten options after a reset")
        XCTAssertFalse(app.buttons["cycleOption.11"].exists)

        app.buttons["openSettings"].tap()
        let optionsStepper = app.steppers["optionCountStepper"]
        XCTAssertTrue(optionsStepper.waitForExistence(timeout: 5),
                      "settings should show the options stepper")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "settings"
        shot.lifetime = .keepAlways
        add(shot)

        optionsStepper.buttons.element(boundBy: 0).tap()   // decrement
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["cycleOption.9"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cycleOption.10"].exists,
                       "the tenth option should be gone")

        resetSettings(in: app)
    }

    private func resetSettings(in app: XCUIApplication) {
        app.buttons["openSettings"].tap()

        // The Form renders lazily, so the reset button may not exist until it
        // has been scrolled into view.
        let reset = app.buttons["resetSettings"]
        if !reset.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "settings should offer a reset")
        reset.tap()
        app.buttons["Done"].tap()
    }
}
