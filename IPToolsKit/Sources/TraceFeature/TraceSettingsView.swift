// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

public struct TraceSettingsView: View {
    @Bindable private var settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Toggle("Resolve hostnames", isOn: $settings.trace.resolveHostnames)
            Toggle("Look up AS numbers", isOn: $settings.trace.lookUpASNs)
        }
        .navigationTitle("Traceroute Settings")
    }
}
