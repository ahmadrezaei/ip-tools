// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

public struct PingView: View {
    @Bindable private var model: PingModel

    public init(model: PingModel) {
        self.model = model
    }

    public var body: some View {
        VStack {
            TargetInputBar(
                text: $model.targetText, placeholder: "Host or IP address", systemImage: "dot.radiowaves.left.and.right",
                mode: .host, primaryTitle: "Ping", isRunning: model.phase == .running,
                isEnabled: !model.targetText.isEmpty, recents: model.recentsStore,
                onSubmit: { model.start() }, onStop: { model.stop() })
            PingStatsGrid(stats: model.stats)
            List(model.samples.reversed()) { PingRow(sample: $0) }
        }
        .navigationTitle("Ping")
    }
}
