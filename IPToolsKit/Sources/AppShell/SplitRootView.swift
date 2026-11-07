// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPFeature
import PingFeature
import SharedUI
import SwiftUI
import TraceFeature

struct SplitRootView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var router = environment.router
        NavigationSplitView {
            Sidebar(selection: $router.selectedTool)
        } detail: {
            NavigationStack {
                switch router.selectedTool {
                case .ping: PingView(model: environment.ping)
                case .traceroute: TraceView(model: environment.trace)
                case .bgp: BGPMapView(model: environment.bgp)
                }
            }
        }
    }
}
