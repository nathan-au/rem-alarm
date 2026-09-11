//
//  REMCycleTests.swift
//  rem-alarmTests
//

import Foundation
import Testing
@testable import rem_alarm

struct REMCycleTests {
    private let start = Date(timeIntervalSince1970: 1_757_540_000)
    private let hundredMinutes: TimeInterval = 100 * 60

    @Test func optionCountMatchesRequest() {
        let options = REMCycle.options(from: start, count: 7,
                                       cycleLength: hundredMinutes, sleepLatency: 0)
        #expect(options.count == 7)
        #expect(options.map(\.cycles) == Array(1...7))
    }

    @Test func zeroOptionsIsEmptyRatherThanACrash() {
        #expect(REMCycle.options(from: start, count: 0,
                                cycleLength: hundredMinutes, sleepLatency: 0).isEmpty)
    }

    @Test func wakeTimesStepByExactlyOneCycle() {
        let options = REMCycle.options(from: start, count: 5,
                                       cycleLength: hundredMinutes, sleepLatency: 0)
        for (earlier, later) in zip(options, options.dropFirst()) {
            #expect(later.wakeTime.timeIntervalSince(earlier.wakeTime) == hundredMinutes)
        }
    }

    /// The buffer models time spent lying awake before the first cycle, so it
    /// must be added once for the whole night — not once per cycle.
    @Test func latencyIsAppliedExactlyOnce() {
        let latency: TimeInterval = 14 * 60
        let options = REMCycle.options(from: start, count: 4,
                                       cycleLength: hundredMinutes, sleepLatency: latency)
        for option in options {
            let expected = start.addingTimeInterval(latency + Double(option.cycles) * hundredMinutes)
            #expect(option.wakeTime == expected)
        }
    }

    /// Latency delays the alarm but isn't time asleep, so it must not inflate
    /// the advertised sleep duration.
    @Test func latencyDoesNotCountAsSleep() {
        let withBuffer = REMCycle.options(from: start, count: 3,
                                          cycleLength: hundredMinutes, sleepLatency: 20 * 60)
        let without = REMCycle.options(from: start, count: 3,
                                       cycleLength: hundredMinutes, sleepLatency: 0)
        #expect(withBuffer.map(\.sleepDuration) == without.map(\.sleepDuration))
        #expect(withBuffer[2].sleepDuration == 3 * hundredMinutes)
    }

    @Test func customCycleLengthDrivesEverything() {
        let ninety: TimeInterval = 90 * 60
        let options = REMCycle.options(from: start, count: 2,
                                       cycleLength: ninety, sleepLatency: 0)
        #expect(options[0].wakeTime == start.addingTimeInterval(ninety))
        #expect(options[1].sleepDuration == 2 * ninety)
    }

    @Test func durationFormatting() {
        let cases: [(minutes: Int, expected: String)] = [
            (300, "5h"),        // whole hours drop the minutes
            (320, "5h 20m"),
            (45, "45m"),        // under an hour drops the hours
            (100, "1h 40m"),
        ]
        for (minutes, expected) in cases {
            let seconds = TimeInterval(minutes * 60)
            #expect(seconds.sleepDurationText == expected)
        }
    }

    @Test func cycleLabelIsSingularOnlyForOne() {
        let options = REMCycle.options(from: start, count: 2,
                                       cycleLength: hundredMinutes, sleepLatency: 0)
        #expect(options[0].cycleLabel == "1 cycle")
        #expect(options[1].cycleLabel == "2 cycles")
    }
}

struct SleepSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return suite
    }

    @Test func defaultsMatchTheDocumentedValues() {
        let settings = SleepSettings(defaults: freshDefaults())
        #expect(settings.cycleMinutes == 100)
        #expect(settings.latencyMinutes == 0)
        #expect(settings.optionCount == 10)
    }

    @Test func valuesRoundTripThroughStorage() {
        let defaults = freshDefaults()
        let first = SleepSettings(defaults: defaults)
        first.cycleMinutes = 90
        first.latencyMinutes = 14
        first.optionCount = 5

        let second = SleepSettings(defaults: defaults)
        #expect(second.cycleMinutes == 90)
        #expect(second.latencyMinutes == 14)
        #expect(second.optionCount == 5)
    }

    /// A stale or hand-edited preference must not be able to produce a
    /// nonsensical picker.
    @Test func storedValuesOutsideTheAllowedRangeAreClamped() {
        let defaults = freshDefaults()
        defaults.set(9_999, forKey: "cycleMinutes")
        defaults.set(-5, forKey: "latencyMinutes")
        defaults.set(0, forKey: "optionCount")

        let settings = SleepSettings(defaults: defaults)
        #expect(settings.cycleMinutes == SleepSettings.cycleRange.upperBound)
        #expect(settings.latencyMinutes == SleepSettings.latencyRange.lowerBound)
        #expect(settings.optionCount == SleepSettings.optionRange.lowerBound)
    }

    @Test func resetRestoresDefaults() {
        let settings = SleepSettings(defaults: freshDefaults())
        settings.cycleMinutes = 75
        settings.optionCount = 12
        settings.resetToDefaults()
        #expect(settings.cycleMinutes == 100)
        #expect(settings.optionCount == 10)
    }
}
