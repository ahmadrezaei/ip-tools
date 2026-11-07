// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public enum RTTColor {
    /// < 80 ms green, 80-199 ms orange, >= 200 ms red, nil (timeout) grey.
    public static func color(for seconds: TimeInterval?) -> Color {
        guard let seconds else { return Color.secondary.opacity(0.6) }
        if seconds < 0.080 { return .green }
        if seconds < 0.200 { return .orange }
        return .red
    }
}
