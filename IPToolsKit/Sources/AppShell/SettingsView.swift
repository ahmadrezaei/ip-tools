// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import PingFeature
import SharedUI
import SwiftUI
import TraceFeature

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            NavigationLink("Ping") { PingSettingsView(settings: environment.settings) }
            NavigationLink("Traceroute") { TraceSettingsView(settings: environment.settings) }
            NavigationLink("About") { AboutView(environment: environment) }
        }
        .navigationTitle("Settings")
    }
}
