// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

public struct PingSettingsView: View {
    @Bindable private var settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Stepper("Interval: \(settings.ping.interval, specifier: "%.1f") s",
                    value: $settings.ping.interval, in: 0.2...5, step: 0.1)
        }
        .navigationTitle("Ping Settings")
    }
}
