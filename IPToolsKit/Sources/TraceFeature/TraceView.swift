// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

public struct TraceView: View {
    @Bindable private var model: TraceModel

    public init(model: TraceModel) {
        self.model = model
    }

    public var body: some View {
        VStack {
            TargetInputBar(
                text: $model.targetText, placeholder: "Host or IP address",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                mode: .host, primaryTitle: "Trace", isRunning: { if case .tracing = model.phase { true } else { false } }(),
                isEnabled: !model.targetText.isEmpty, recents: model.recentsStore,
                onSubmit: { model.start() }, onStop: { model.stop() })
            TraceSummaryCard(hops: model.hops)
            List(model.hops) { HopRow(hop: $0) }
        }
        .navigationTitle("Traceroute")
    }
}
