//
//  REMAlarmLiveActivity.swift
//  REMAlarmWidget
//
//  AlarmKit drives this Live Activity itself. The app never starts or stops it:
//  scheduling an alarm whose attributes are AlarmAttributes<REMAlarmMetadata>
//  is what makes the system look for a matching ActivityConfiguration here.
//

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

struct REMAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<REMAlarmMetadata>.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Palette.card)
                .activitySystemActionForegroundColor(Palette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isAlerting ? "sun.max.fill" : "moon.zzz.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusText(context: context)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.primaryText)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(subtitle(for: context))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            } compactLeading: {
                Image(systemName: context.state.isAlerting ? "sun.max.fill" : "moon.zzz.fill")
                    .foregroundStyle(Palette.accent)
            } compactTrailing: {
                StatusText(context: context)
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent)
            } minimal: {
                Image(systemName: context.state.isAlerting ? "sun.max.fill" : "moon.zzz.fill")
                    .foregroundStyle(Palette.accent)
            }
            .keylineTint(Palette.accent)
        }
    }

    private func subtitle(for context: ActivityViewContext<AlarmAttributes<REMAlarmMetadata>>) -> String {
        guard let cycles = context.attributes.metadata?.cycleLabel else { return "REM Alarm" }
        return context.state.isAlerting ? "\(cycles) complete" : "\(cycles) of sleep"
    }
}

// MARK: - Lock screen

private struct LockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<REMAlarmMetadata>>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.isAlerting ? "sun.max.fill" : "moon.zzz.fill")
                .font(.title)
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.accent.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.isAlerting ? "Time to wake up" : "Wake in")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                StatusText(context: context)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.primaryText)
            }

            Spacer(minLength: 8)

            if let metadata = context.attributes.metadata {
                VStack(spacing: -2) {
                    Text("\(metadata.cycles)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text(metadata.cycles == 1 ? "cycle" : "cycles")
                        .font(.system(size: 9, weight: .medium))
                        .textCase(.uppercase)
                }
                .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The one piece of text that changes: a live countdown while the alarm is
/// pending, the wake time once it's ringing.
private struct StatusText: View {
    let context: ActivityViewContext<AlarmAttributes<REMAlarmMetadata>>

    var body: some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
        case .paused(let paused):
            Text(remaining(of: paused).sleepDurationText)
        case .alert(let alert):
            Text(String(format: "%d:%02d", alert.time.hour, alert.time.minute))
        @unknown default:
            Text("REM Alarm")
        }
    }

    private func remaining(of paused: AlarmPresentationState.Mode.Paused) -> TimeInterval {
        max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
    }
}

private extension AlarmPresentationState {
    var isAlerting: Bool {
        if case .alert = mode { return true }
        return false
    }
}

private extension TimeInterval {
    var sleepDurationText: String {
        let totalMinutes = Int((self / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
