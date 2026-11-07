// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Charts
import NetCore
import SwiftUI

struct PingChart: View {
    let samples: [PingSample]

    var body: some View {
        Chart(samples) { sample in
            if case let .reply(rtt, _, _, _) = sample.outcome {
                LineMark(x: .value("Sequence", sample.sequence), y: .value("RTT (ms)", rtt * 1000))
            }
        }
        .frame(height: 120)
    }
}
