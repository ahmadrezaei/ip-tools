// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

private struct IsOnlineKey: EnvironmentKey { static let defaultValue = true }
private struct TargetFocusTokenKey: EnvironmentKey { static let defaultValue = 0 }
private struct AboutSectionKey: EnvironmentKey { static var defaultValue: AnyView? { nil } }

public extension EnvironmentValues {
    /// Network reachability, injected by the app shell. `TargetInputBar` disables its primary button and shows
    /// the offline banner when this is false. Defaults to true (previews, tests).
    var isOnline: Bool {
        get { self[IsOnlineKey.self] }
        set { self[IsOnlineKey.self] = newValue }
    }

    /// Bumped by the app shell (⌘L); `TargetInputBar` focuses its field when the value changes.
    var targetFocusToken: Int {
        get { self[TargetFocusTokenKey.self] }
        set { self[TargetFocusTokenKey.self] = newValue }
    }

    /// Content the app shell appends to each tool's settings sheet (the About section).
    var aboutSection: AnyView? {
        get { self[AboutSectionKey.self] }
        set { self[AboutSectionKey.self] = newValue }
    }
}
