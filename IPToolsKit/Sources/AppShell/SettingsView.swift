// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import PingFeature
import SharedUI
import SwiftUI
import TraceFeature

/// Combined settings (iPad sidebar footer): all tools' settings plus About.
struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            Section("Tools") {
                NavigationLink("Ping") { PingSettingsView(settings: environment.settings, showsAbout: false) }
                NavigationLink("Traceroute") { TraceSettingsView(settings: environment.settings, showsAbout: false) }
            }
            AboutSections(environment: environment)
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView(environment: .preview()) }
}
