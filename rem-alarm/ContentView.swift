//
//  ContentView.swift
//  rem-alarm
//
//  Created by Nathan Au on 2026-09-10.
//

import SwiftUI

struct ContentView: View {
    @State private var scheduler = AlarmScheduler()
    @State private var settings = SleepSettings()
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            if let armed = scheduler.armed {
                ArmedView(armed: armed) { scheduler.cancel() }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                CyclePickerView(settings: settings) { option in
                    Task { await scheduler.arm(option) }
                } onOpenSettings: {
                    showingSettings = true
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: scheduler.armed)
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
        .task { await scheduler.observeAlarms() }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
        .alert("Alarms are turned off", isPresented: $scheduler.authorizationDenied) {
            Button("Open Settings") { openSystemSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("REM Alarm needs permission to schedule alarms so it can wake you through silent mode and Focus.")
        }
        .alert("Something went wrong", isPresented: showingError) {
            Button("OK") {}
        } message: {
            Text(scheduler.errorMessage ?? "")
        }
    }

    private var showingError: Binding<Bool> {
        Binding(
            get: { scheduler.errorMessage != nil },
            set: { if !$0 { scheduler.errorMessage = nil } }
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Picker

/// The cycle choices. Times are relative to now, so the list re-renders
/// periodically to stay honest as the clock moves.
private struct CyclePickerView: View {
    let settings: SleepSettings
    let onSelect: (CycleOption) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(spacing: 10) {
                        ForEach(options(at: context.date)) { option in
                            CycleRow(option: option) { onSelect(option) }
                        }
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }

    private func options(at date: Date) -> [CycleOption] {
        REMCycle.options(from: date,
                         count: settings.optionCount,
                         cycleLength: settings.cycleLength,
                         sleepLatency: settings.sleepLatency)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sleep now, wake at")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer(minLength: 12)

            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Palette.card, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("openSettings")
        }
        .padding(.bottom, 4)
    }

    /// Spells out the falling-asleep buffer when there is one. Without this the
    /// offset times just look wrong.
    private var subtitle: String {
        let base = "Cycles are \(settings.cycleMinutes) minutes."
        guard settings.latencyMinutes > 0 else { return base }
        return base + " Assuming \(settings.latencyMinutes) min to fall asleep."
    }

    private var footer: some View {
        Text("Waking at the end of a cycle beats waking in the middle of one.")
            .font(.footnote)
            .foregroundStyle(Palette.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }
}

private struct CycleRow: View {
    let option: CycleOption
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                CycleBadge(cycles: option.cycles)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.wakeTime.wakeTimeText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Palette.primaryText)
                        .monospacedDigit()
                    Text("\(option.sleepDuration.sleepDurationText) of sleep")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Palette.card, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cycleOption.\(option.cycles)")
    }
}

private struct CycleBadge: View {
    let cycles: Int

    var body: some View {
        VStack(spacing: -2) {
            Text("\(cycles)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(cycles == 1 ? "cycle" : "cycles")
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
        }
        .foregroundStyle(Palette.accent)
        .frame(width: 52, height: 52)
        .background(Palette.accent.opacity(0.14), in: .circle)
    }
}

// MARK: - Armed

private struct ArmedView: View {
    let armed: ArmedAlarm
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 34))
                .foregroundStyle(Palette.accent)

            VStack(spacing: 6) {
                Text("Alarm set for")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                Text(armed.wakeTime.wakeTimeText)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primaryText)
                    .monospacedDigit()
                Text("\(armed.cycleLabel) · \(armed.sleepDuration.sleepDurationText) of sleep")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }

            Text(armed.wakeTime, style: .timer)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryText)

            Button("Cancel alarm", role: .destructive, action: onCancel)
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.top, 4)
        }
        .padding(32)
        .background(Palette.card, in: .rect(cornerRadius: 24))
        .padding(24)
    }
}

#Preview {
    ContentView()
}
