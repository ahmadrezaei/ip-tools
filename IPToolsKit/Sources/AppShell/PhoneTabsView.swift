// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPFeature
import PingFeature
import SharedUI
import SwiftUI
import TraceFeature

struct PhoneTabsView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var router = environment.router
        TabView(selection: $router.selectedTool) {
            NavigationStack { PingView(model: environment.ping) }
                .tabItem { Label(Tool.ping.title, systemImage: Tool.ping.systemImage) }
                .tag(Tool.ping)
            NavigationStack { TraceView(model: environment.trace) }
                .tabItem { Label(Tool.traceroute.title, systemImage: Tool.traceroute.systemImage) }
                .tag(Tool.traceroute)
            NavigationStack { BGPMapView(model: environment.bgp) }
                .tabItem { Label(Tool.bgp.title, systemImage: Tool.bgp.systemImage) }
                .tag(Tool.bgp)
            NavigationStack { SettingsView(environment: environment) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
