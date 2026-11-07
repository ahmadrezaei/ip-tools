// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

public struct BGPMapView: View {
    @Bindable private var model: BGPMapModel

    public init(model: BGPMapModel) {
        self.model = model
    }

    public var body: some View {
        VStack {
            TargetInputBar(
                text: $model.targetText, placeholder: "IP, prefix or AS number",
                systemImage: "point.3.connected.trianglepath.dotted",
                mode: .bgp, primaryTitle: "Map", isRunning: { if case .loading = model.phase { true } else { false } }(),
                isEnabled: !model.targetText.isEmpty, recents: model.recentsStore,
                onSubmit: { model.map() }, onStop: { model.cancel() })
            PrefixHeaderCard(result: model.result)
            GraphCanvasView(model: model)
        }
        .navigationTitle("BGP Map")
    }
}
