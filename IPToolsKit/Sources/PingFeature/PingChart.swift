// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Accessibility
import Charts
import NetCore
import SharedUI
import SwiftUI

/// RTT over sequence number: line + points for replies (the line breaks at timeouts), red crosses on the
/// baseline for timeouts, a dashed average rule. Shows the last 60 samples.
struct PingChart: View {
    let samples: [PingSample]
    let average: TimeInterval?

    static let window = 60

    private struct Point: Identifiable {
        let id: Int
        let sequence: Int
        let rtt: Double?       // ms
        let segment: Int
    }

    private var points: [Point] {
        var segment = 0
        return samples.suffix(Self.window).map { sample in
            if case let .reply(rtt, _, _, _) = sample.outcome {
                return Point(id: sample.sequence, sequence: sample.sequence, rtt: rtt * 1000, segment: segment)
            }
            segment += 1
            return Point(id: sample.sequence, sequence: sample.sequence, rtt: nil, segment: segment)
        }
    }

    static func niceMax(_ value: Double) -> Double {
        let target = max(value * 1.2, 10)
        let magnitude = pow(10, floor(log10(target)))
        for step in [1.0, 2.0, 2.5, 5.0, 10.0] where step * magnitude >= target {
            return step * magnitude
        }
        return 10 * magnitude
    }

    var body: some View {
        let points = self.points
        let maxRTT = points.compactMap(\.rtt).max() ?? 0
        let lo = points.first?.sequence ?? 0
        let hi = max(points.last?.sequence ?? 1, lo + 1)
        Chart {
            ForEach(points) { point in
                if let rtt = point.rtt {
                    LineMark(x: .value("Sequence", point.sequence), y: .value("RTT (ms)", rtt),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Sequence", point.sequence), y: .value("RTT (ms)", rtt))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(18)
                } else {
                    PointMark(x: .value("Sequence", point.sequence), y: .value("RTT (ms)", 0))
                        .foregroundStyle(.red)
                        .symbol(.cross)
                        .symbolSize(50)
                }
            }
            if let average {
                RuleMark(y: .value("Average", average * 1000))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYScale(domain: 0...Self.niceMax(maxRTT))
        .chartXScale(domain: lo...hi)
        .chartXAxis {
            AxisMarks(values: [lo, hi]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 140)
        .accessibilityChartDescriptor(PingChartDescriptor(samples: samples))
    }
}

/// VoiceOver "Audio Graph" support plus a one-line summary.
struct PingChartDescriptor: AXChartDescriptorRepresentable {
    let samples: [PingSample]

    private var rtts: [(Int, Double)] {
        samples.compactMap { sample in
            if case let .reply(rtt, _, _, _) = sample.outcome { return (sample.sequence, rtt * 1000) }
            return nil
        }
    }

    var summary: String {
        let values = rtts.map(\.1)
        guard let min = values.min(), let max = values.max() else {
            return String(localized: "\(samples.count) samples, no replies")
        }
        let avg = values.reduce(0, +) / Double(values.count)
        return String(localized: "\(samples.count) samples, min \(String(format: "%.1f", min)), avg \(String(format: "%.1f", avg)), max \(String(format: "%.1f", max)) ms")
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let data = rtts
        let xs = data.map { Double($0.0) }
        let ys = data.map(\.1)
        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Sequence"),
            range: (xs.min() ?? 0)...max(xs.max() ?? 1, (xs.min() ?? 0) + 1),
            gridlinePositions: []
        ) { value in String(Int(value)) }
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Round-trip time (ms)"),
            range: 0...max(ys.max() ?? 1, 1),
            gridlinePositions: []
        ) { value in String(format: "%.1f ms", value) }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "RTT"), isContinuous: false,
            dataPoints: data.map { AXDataPoint(x: Double($0.0), y: $0.1) }
        )
        return AXChartDescriptor(title: String(localized: "Ping round-trip times"), summary: summary,
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let fresh = makeChartDescriptor()
        descriptor.summary = fresh.summary
        descriptor.series = fresh.series
    }
}
