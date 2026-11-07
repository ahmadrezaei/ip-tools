// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

struct PingStatsGrid: View {
    let stats: PingStatistics

    var body: some View {
        HStack {
            stat("Sent", "\(stats.sent)")
            stat("Loss", Format.percent(stats.lossFraction))
            stat("Avg", stats.avg.map(Format.rtt) ?? "-")
        }
        .padding(.horizontal)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
