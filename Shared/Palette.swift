//
//  Palette.swift
//  Shared between the app and the widget extension.
//

import SwiftUI

/// Flat colours only — no gradients anywhere in this app, and nothing in the
/// violet/indigo family. The accent is a warm amber, which reads as sunrise
/// rather than nightclub and stays legible on a near-black background.
enum Palette {
    /// Neutral near-black. Deliberately not blue-tinted, so it never drifts purple.
    static let background = Color(red: 0.05, green: 0.05, blue: 0.055)
    static let card = Color(red: 0.12, green: 0.12, blue: 0.125)
    static let accent = Color(red: 0.97, green: 0.71, blue: 0.28)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
}
