//
//  ContentView.swift
//  rem-alarm
//
//  Created by Nathan Au on 2026-09-10.
//

import SwiftUI

struct ContentView: View {
    @State private var scheduler = AlarmScheduler()

    var body: some View {
        ZStack {
            Color.nightBackground.ignoresSafeArea()

            if let armed = scheduler.armed {
                ArmedView(armed: armed) { scheduler.cancel() }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                CyclePickerView { option in
                    Task { await scheduler.arm(option) }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: scheduler.armed)
        .preferredColorScheme(.dark)
        .task { await scheduler.observeAlarms() }
        .alert("Alarms are turned off", isPresented: $scheduler.authorizationDenied) {
            Button("Open Settings") { openSettings() }
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

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Picker

/// The ten choices. Times are relative to now, so they re-render every minute.
private struct CyclePickerView: View {
    let onSelect: (CycleOption) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(spacing: 10) {
                        ForEach(REMCycle.options(from: context.date)) { option in
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep now, wake at")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
            Text("Pick how many sleep cycles you want. Cycles are \(Int(REMCycle.length / 60)) minutes.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.bottom, 4)
    }

    private var footer: some View {
        Text("Waking at the end of a cycle beats waking in the middle of one.")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.4))
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
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("\(option.sleepDuration.sleepDurationText) of sleep")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.nightCard, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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
        .foregroundStyle(Color.accentIndigo)
        .frame(width: 52, height: 52)
        .background(Color.accentIndigo.opacity(0.15), in: .circle)
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
                .foregroundStyle(Color.accentIndigo)

            VStack(spacing: 6) {
                Text("Alarm set for")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                Text(armed.wakeTime.wakeTimeText)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("\(armed.cycles) \(armed.cycles == 1 ? "cycle" : "cycles") · \(Double(armed.cycles).sleepCycleDurationText) of sleep")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text(armed.wakeTime, style: .timer)
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.35))

            Button("Cancel alarm", role: .destructive, action: onCancel)
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.top, 4)
        }
        .padding(32)
        .background(Color.nightCard, in: .rect(cornerRadius: 24))
        .padding(24)
    }
}

private extension Double {
    /// Convenience for the armed card: cycles -> "6h 40m".
    var sleepCycleDurationText: String {
        (self * REMCycle.length).sleepDurationText
    }
}

// MARK: - Palette

private extension Color {
    static let nightBackground = Color(red: 0.04, green: 0.04, blue: 0.08)
    static let nightCard = Color(red: 0.10, green: 0.10, blue: 0.16)
    static let accentIndigo = Color(red: 0.55, green: 0.55, blue: 0.98)
}

#Preview {
    ContentView()
}
