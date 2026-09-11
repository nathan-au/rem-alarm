//
//  REMAlarmMetadata.swift
//  Shared between the app and the widget extension.
//
//  Both targets must compile the *same* metadata type: the app declares
//  AlarmAttributes<REMAlarmMetadata> when scheduling, and the widget declares
//  the matching ActivityConfiguration. If the types diverge, the system simply
//  never renders the Live Activity.
//

import AlarmKit
import Foundation

struct REMAlarmMetadata: AlarmMetadata {
    let cycles: Int

    init(cycles: Int) {
        self.cycles = cycles
    }

    var cycleLabel: String {
        "\(cycles) \(cycles == 1 ? "cycle" : "cycles")"
    }
}
