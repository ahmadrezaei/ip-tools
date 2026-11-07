// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public enum RTTColor {
    /// Below this (seconds) an RTT is green.
    public static let goodThreshold: TimeInterval = 0.080
    /// At or above this (seconds) an RTT is red; in between it is orange.
    public static let badThreshold: TimeInterval = 0.200

    /// < 80 ms green, 80-199 ms orange, >= 200 ms red, nil (timeout) grey.
    public static func color(for seconds: TimeInterval?) -> Color {
        guard let seconds else { return Color.secondary.opacity(0.6) }
        if seconds < goodThreshold { return .green }
        if seconds < badThreshold { return .orange }
        return .red
    }

    /// Loss colour: orange when > 0, red when >= 50 %, otherwise primary.
    public static func lossColor(_ fraction: Double) -> Color {
        if fraction >= 0.5 { return .red }
        if fraction > 0 { return .orange }
        return .primary
    }
}
