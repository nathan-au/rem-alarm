//
//  SettingsView.swift
//  rem-alarm
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SleepSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StepperRow(title: "Cycle length",
                               value: "\(settings.cycleMinutes) min",
                               identifier: "cycleLengthStepper",
                               selection: $settings.cycleMinutes,
                               range: SleepSettings.cycleRange,
                               step: SleepSettings.cycleStep)
                } header: {
                    Text("Sleep cycle")
                } footer: {
                    Text("One full cycle, start to finish. Most people land between 80 and 110 minutes; the default of \(SleepSettings.defaultCycleMinutes) is only an average.")
                }

                Section {
                    StepperRow(title: "Time to fall asleep",
                               value: settings.latencyMinutes == 0 ? "None" : "\(settings.latencyMinutes) min",
                               identifier: "latencyStepper",
                               selection: $settings.latencyMinutes,
                               range: SleepSettings.latencyRange,
                               step: SleepSettings.latencyStep)
                } header: {
                    Text("Falling asleep")
                } footer: {
                    Text("Added once, before the first cycle starts. Without it every alarm fires slightly early, because the clock starts when you tap — not when you actually drop off.")
                }

                Section {
                    StepperRow(title: "Options shown",
                               value: "\(settings.optionCount)",
                               identifier: "optionCountStepper",
                               selection: $settings.optionCount,
                               range: SleepSettings.optionRange,
                               step: 1)
                } header: {
                    Text("Picker")
                } footer: {
                    Text("How many cycle choices to list. Trimming the list to the few you'd realistically pick makes the decision faster when you're already half asleep.")
                }

                Section {
                    Button("Reset to defaults") { settings.resetToDefaults() }
                        .foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("resetSettings")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Palette.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .tint(Palette.accent)
        }
    }
}

/// A stepper that shows its value with a unit ("100 min") rather than a bare
/// number. `Stepper(value:in:step:)` handles clamping and disabling the
/// +/- buttons at the ends of the range.
private struct StepperRow: View {
    let title: String
    let value: String
    let identifier: String
    @Binding var selection: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        Stepper(value: $selection, in: range, step: step) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent)
            }
        }
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    SettingsView(settings: SleepSettings())
}
