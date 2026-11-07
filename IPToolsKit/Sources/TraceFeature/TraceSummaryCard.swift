// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

struct TraceSummaryCard: View {
    let hops: [TraceHop]

    var body: some View {
        Text("\(hops.count) hops").font(.footnote).foregroundStyle(.secondary)
    }
}
