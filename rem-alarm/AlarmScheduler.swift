//
//  AlarmScheduler.swift
//  rem-alarm
//

import AlarmKit
import Foundation
import SwiftUI

/// The single alarm the user has armed for tonight.
///
/// Carries its own `sleepDuration` rather than recomputing it from the current
/// settings: changing the cycle length after arming must not retroactively
/// rewrite what an already-scheduled alarm claims to be.
struct ArmedAlarm: Codable, Equatable {
    let id: UUID
    let cycles: Int
    let wakeTime: Date
    let sleepDuration: TimeInterval

    var cycleLabel: String {
        "\(cycles) \(cycles == 1 ? "cycle" : "cycles")"
    }
}

/// Wraps AlarmKit. Only one alarm is ever armed at a time — you only fall
/// asleep once per night.
@MainActor
@Observable
final class AlarmScheduler {
    private(set) var armed: ArmedAlarm?
    var authorizationDenied = false
    var errorMessage: String?

    private let manager = AlarmManager.shared
    private let storageKey = "armedAlarm"

    init() {
        armed = loadArmed()
    }

    // MARK: - Arming

    func arm(_ option: CycleOption) async {
        guard await ensureAuthorized() else { return }

        let id = UUID()
        // No stop button is supplied: since iOS 26.1 the system renders its own.
        let alert = AlarmPresentation.Alert(
            title: "\(option.cycleLabel) of sleep"
        )
        // No pause button: pausing an alarm you are asleep behind is a footgun,
        // and omitting the button is what keeps it off the Live Activity.
        let countdown = AlarmPresentation.Countdown(title: "Sleeping")
        let attributes = AlarmAttributes<REMAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown),
            metadata: REMAlarmMetadata(cycles: option.cycles),
            tintColor: Palette.accent
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(
                preAlert: option.wakeTime.timeIntervalSinceNow,
                postAlert: nil
            ),
            schedule: .fixed(option.wakeTime),
            attributes: attributes
        )

        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            // Required for the Live Activity. A freshly scheduled alarm sits in
            // `.scheduled` state and AlarmKit creates no activity for it —
            // verified in the logs: without this call you get no activity at all
            // and cancelling reports `unknownAlarm`. Moving it to `.countdown`
            // is what makes AlarmKit create the Lock Screen activity.
            try manager.countdown(id: id)
            setArmed(ArmedAlarm(id: id, cycles: option.cycles,
                                wakeTime: option.wakeTime,
                                sleepDuration: option.sleepDuration))
        } catch {
            errorMessage = "Couldn't set the alarm: \(error.localizedDescription)"
        }
    }

    func cancel() {
        guard let armed else { return }
        try? manager.cancel(id: armed.id)
        setArmed(nil)
    }

    // MARK: - Authorization

    private func ensureAuthorized() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            authorizationDenied = false
            return true
        case .denied:
            authorizationDenied = true
            return false
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                authorizationDenied = (state == .denied)
                return state == .authorized
            } catch {
                errorMessage = "Couldn't ask for alarm permission: \(error.localizedDescription)"
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Staying in sync with the system

    /// AlarmKit owns the truth. If the user stops or dismisses the alarm from
    /// the system alert, it disappears from `alarms` and we drop back to the
    /// picker.
    func observeAlarms() async {
        for await alarms in manager.alarmUpdates {
            guard let current = armed else { continue }
            if !alarms.contains(where: { $0.id == current.id }) {
                setArmed(nil)
            }
        }
    }

    // MARK: - Persistence

    private func setArmed(_ value: ArmedAlarm?) {
        armed = value
        if let value, let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    private func loadArmed() -> ArmedAlarm? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(ArmedAlarm.self, from: data)
        else { return nil }
        // A wake time in the past means the alarm already rang while we weren't running.
        return stored.wakeTime > .now ? stored : nil
    }
}
