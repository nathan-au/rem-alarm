//
//  REMCycle.swift
//  rem-alarm
//

import Foundation

/// The sleep-cycle math behind every alarm in the app.
///
/// The user never picks a clock time. They pick a number of cycles, and the
/// wake time falls out of that.
///
/// Deliberately a pure, parameterised namespace rather than something that
/// reads `SleepSettings` itself — the arithmetic here is the whole product, and
/// keeping it dependency-free is what makes it cheap to test.
enum REMCycle {

    /// `start + latency + (cycles × length)`.
    ///
    /// Latency is added exactly once, not once per cycle: it models the time
    /// spent lying awake before the first cycle begins.
    static func wakeTime(cycles: Int,
                         from start: Date,
                         cycleLength: TimeInterval,
                         sleepLatency: TimeInterval) -> Date {
        start.addingTimeInterval(sleepLatency + Double(cycles) * cycleLength)
    }

    /// The ladder of choices, measured from `start`.
    static func options(from start: Date,
                        count: Int,
                        cycleLength: TimeInterval,
                        sleepLatency: TimeInterval) -> [CycleOption] {
        guard count > 0 else { return [] }
        return (1...count).map { cycles in
            CycleOption(
                cycles: cycles,
                wakeTime: wakeTime(cycles: cycles, from: start,
                                   cycleLength: cycleLength, sleepLatency: sleepLatency),
                sleepDuration: Double(cycles) * cycleLength
            )
        }
    }
}

struct CycleOption: Identifiable, Hashable {
    let cycles: Int
    let wakeTime: Date
    /// Time actually asleep — excludes the falling-asleep buffer, because the
    /// user isn't asleep during it.
    let sleepDuration: TimeInterval

    var id: Int { cycles }

    var cycleLabel: String {
        "\(cycles) \(cycles == 1 ? "cycle" : "cycles")"
    }
}

extension TimeInterval {
    /// "6h 40m" — the amount of sleep a choice buys you.
    var sleepDurationText: String {
        let totalMinutes = Int((self / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

extension Date {
    /// "4:20 AM", in the user's locale.
    var wakeTimeText: String {
        formatted(date: .omitted, time: .shortened)
    }
}
