//
//  AlarmFiringTests.swift
//  rem-alarmTests
//
//  End-to-end check that the scheduling configuration actually rings, rather
//  than merely being accepted. Slow by nature (it waits out a real alarm), but
//  it covers the one failure that matters most: an alarm that never fires.
//

import AlarmKit
import Foundation
import Testing
@testable import rem_alarm

@MainActor
struct AlarmFiringTests {
    @Test func armedAlarmActuallyReachesAlertingState() async throws {
        // A unit test can't tap the system permission prompt. On a freshly reset
        // simulator, skip rather than report a misleading failure — the UI test
        // is what exercises the authorization flow.
        guard AlarmManager.shared.authorizationState == .authorized else { return }

        let scheduler = AlarmScheduler()
        let option = CycleOption(cycles: 1,
                                 wakeTime: Date.now.addingTimeInterval(15),
                                 sleepDuration: 15)
        await scheduler.arm(option)

        let armed = try #require(scheduler.armed, "alarm should be armed")

        var sawCountdown = false
        var sawAlerting = false
        let deadline = Date.now.addingTimeInterval(45)

        while Date.now < deadline, !sawAlerting {
            let alarm = try? AlarmManager.shared.alarms.first { $0.id == armed.id }
            if let state = alarm?.state {
                if state == .countdown { sawCountdown = true }
                if state == .alerting { sawAlerting = true }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        try? AlarmManager.shared.stop(id: armed.id)

        #expect(sawCountdown, "alarm should sit in countdown while pending")
        #expect(sawAlerting, "alarm should reach alerting when the wake time arrives")
    }
}
