// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

/// 3 x 2 grid: Min, Avg, Max, Jitter, Loss, Received.
struct PingStatsGrid: View {
    let stats: PingStatistics

    private func value(_ seconds: TimeInterval?) -> String {
        seconds.map { Format.ms($0) } ?? "--"
    }

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 14) {
            GridRow {
                stat("Min", value(stats.min), unit: stats.min != nil)
                stat("Avg", value(stats.avg), unit: stats.avg != nil)
                stat("Max", value(stats.max), unit: stats.max != nil)
            }
            GridRow {
                stat("Jitter", value(stats.jitter), unit: stats.jitter != nil)
                stat("Loss", stats.sent == 0 ? "--" : Format.percent(stats.lossFraction), color: RTTColor.lossColor(stats.lossFraction))
                stat("Received", stats.sent == 0 ? "--" : "\(stats.received) of \(stats.sent)")
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, unit: Bool = false, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(unit ? "\(value) milliseconds" : value))
    }
}

#Preview {
    VStack {
        PingStatsGrid(stats: PingStatistics(samples: [PingSample]()))
        PingStatsGrid(stats: PingStatistics(samples: [
            PingSample(sequence: 0, sentAt: Date(), outcome: .reply(rtt: 0.0118, bytes: 64, ttl: 58, from: IPAddress("1.1.1.1")!)),
            PingSample(sequence: 1, sentAt: Date(), outcome: .reply(rtt: 0.0223, bytes: 64, ttl: 58, from: IPAddress("1.1.1.1")!)),
            PingSample(sequence: 2, sentAt: Date(), outcome: .timeout),
        ]))
    }
    .padding()
}
