//
//  SleepSettings.swift
//  rem-alarm
//

import Foundation
import Observation

/// The three numbers the user controls. Everything on the picker screen is
/// derived from these.
///
/// Stored in minutes rather than `TimeInterval` because that's the unit the
/// user actually thinks and edits in; the conversion happens at the edge.
@Observable
final class SleepSettings {
    /// How long one sleep cycle lasts, in minutes.
    var cycleMinutes: Int {
        didSet { persist(cycleMinutes, Key.cycleMinutes) }
    }

    /// How long the user expects to lie awake before actually falling asleep,
    /// in minutes. Pushes every wake time later by a fixed amount.
    var latencyMinutes: Int {
        didSet { persist(latencyMinutes, Key.latencyMinutes) }
    }

    /// How many cycle choices to list.
    var optionCount: Int {
        didSet { persist(optionCount, Key.optionCount) }
    }

    // MARK: - Allowed ranges

    static let cycleRange = 60...140
    static let cycleStep = 5
    static let latencyRange = 0...60
    static let latencyStep = 1
    static let optionRange = 3...12

    static let defaultCycleMinutes = 100
    static let defaultLatencyMinutes = 0
    static let defaultOptionCount = 10

    // MARK: - Derived

    var cycleLength: TimeInterval { TimeInterval(cycleMinutes * 60) }
    var sleepLatency: TimeInterval { TimeInterval(latencyMinutes * 60) }

    // MARK: - Lifecycle

    private enum Key {
        static let cycleMinutes = "cycleMinutes"
        static let latencyMinutes = "latencyMinutes"
        static let optionCount = "optionCount"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cycleMinutes = Self.read(Key.cycleMinutes, default: Self.defaultCycleMinutes,
                                 in: Self.cycleRange, from: defaults)
        latencyMinutes = Self.read(Key.latencyMinutes, default: Self.defaultLatencyMinutes,
                                   in: Self.latencyRange, from: defaults)
        optionCount = Self.read(Key.optionCount, default: Self.defaultOptionCount,
                                in: Self.optionRange, from: defaults)
    }

    func resetToDefaults() {
        cycleMinutes = Self.defaultCycleMinutes
        latencyMinutes = Self.defaultLatencyMinutes
        optionCount = Self.defaultOptionCount
    }

    private func persist(_ value: Int, _ key: String) {
        defaults.set(value, forKey: key)
    }

    /// Missing keys fall back to the default; out-of-range values are clamped
    /// rather than trusted, so a stale or hand-edited preference can't produce
    /// a nonsensical list of alarms.
    private static func read(_ key: String, default fallback: Int,
                             in range: ClosedRange<Int>, from defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return min(max(defaults.integer(forKey: key), range.lowerBound), range.upperBound)
    }
}
