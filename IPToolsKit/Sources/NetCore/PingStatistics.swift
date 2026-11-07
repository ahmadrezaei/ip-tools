// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct PingStatistics: Hashable, Sendable {
    public let sent: Int, received: Int
    public var lossFraction: Double { sent == 0 ? 0 : 1 - Double(received) / Double(sent) }
    public let min: TimeInterval?, avg: TimeInterval?, max: TimeInterval?, stddev: TimeInterval?, jitter: TimeInterval?

    public init(samples: some Collection<PingSample>) {
        var rtts: [TimeInterval] = []
        for sample in samples {
            if case let .reply(rtt, _, _, _) = sample.outcome { rtts.append(rtt) }
        }
        sent = samples.count
        received = rtts.count
        guard !rtts.isEmpty else {
            min = nil; avg = nil; max = nil; stddev = nil; jitter = nil
            return
        }
        let mean = rtts.reduce(0, +) / Double(rtts.count)
        min = rtts.min()
        max = rtts.max()
        avg = mean
        stddev = (rtts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rtts.count)).squareRoot()
        if rtts.count > 1 {
            var total = 0.0
            for i in 1..<rtts.count { total += abs(rtts[i] - rtts[i - 1]) }
            jitter = total / Double(rtts.count - 1)
        } else {
            jitter = nil
        }
    }
}
