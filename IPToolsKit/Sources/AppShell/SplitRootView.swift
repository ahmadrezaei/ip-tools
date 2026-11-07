// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPFeature
import PingFeature
import SharedUI
import SwiftUI
import TraceFeature

struct SplitRootView: View {
    let environment: AppEnvironment
    @State private var showSettings = false

    var body: some View {
        let router = environment.router
        NavigationSplitView {
            Sidebar(environment: environment, showSettings: $showSettings)
        } detail: {
            NavigationStack {
                switch router.selectedTool {
                case .ping: PingView(model: environment.ping)
                case .traceroute: TraceView(model: environment.trace)
                case .bgp: BGPMapView(model: environment.bgp)
                }
            }
            .id(router.selectedTool)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showSettings) {
            SettingsSheet { SettingsView(environment: environment) }
        }
    }
}
