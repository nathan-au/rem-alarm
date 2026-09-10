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

        let firstRow = app.buttons.element(boundBy: 0)
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
}
