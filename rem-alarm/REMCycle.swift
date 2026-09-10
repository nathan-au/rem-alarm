//
//  REMCycle.swift
//  rem-alarm
//

import Foundation

/// The sleep-cycle math behind every alarm in the app.
///
/// The user never picks a clock time. They pick a number of cycles, and the
/// wake time falls out of that.
enum REMCycle {
    /// Length of one sleep cycle. Hardcoded for now; a later version can let
    /// the user tune this to their own measured cycle length.
    static let length: TimeInterval = 100 * 60

    /// How many cycles are offered on the main screen.
    static let count = 10

    static func wakeTime(cycles: Int, from start: Date) -> Date {
        start.addingTimeInterval(Double(cycles) * length)
    }

    /// The full ladder of choices, measured from `start`.
    static func options(from start: Date) -> [CycleOption] {
        (1...count).map { cycles in
            CycleOption(cycles: cycles, wakeTime: wakeTime(cycles: cycles, from: start))
        }
    }
}

struct CycleOption: Identifiable, Hashable {
    let cycles: Int
    let wakeTime: Date

    var id: Int { cycles }

    var sleepDuration: TimeInterval { Double(cycles) * REMCycle.length }
}

extension TimeInterval {
    /// "6h 40m" — the amount of sleep a choice buys you.
    var sleepDurationText: String {
        let totalMinutes = Int((self / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

extension Date {
    /// "4:20 AM", in the user's locale.
    var wakeTimeText: String {
        formatted(date: .omitted, time: .shortened)
    }
}
