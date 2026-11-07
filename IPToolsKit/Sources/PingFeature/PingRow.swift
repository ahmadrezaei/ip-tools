// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

struct PingRow: View {
    let sample: PingSample

    var body: some View {
        HStack {
            Text("#\(sample.sequence + 1)").monospacedDigit().foregroundStyle(.secondary)
            switch sample.outcome {
            case let .reply(rtt, _, _, _):
                Circle().fill(RTTColor.color(for: rtt)).frame(width: 8, height: 8)
                Text(Format.rtt(rtt)).monospacedDigit()
            case .timeout:
                Circle().fill(RTTColor.color(for: nil)).frame(width: 8, height: 8)
                Text("Request timed out")
            case .unreachable:
                Text("Destination unreachable")
            case .error(let error):
                Text(String(describing: error))
            }
        }
    }
}
