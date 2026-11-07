// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import NetCore

@Suite struct PingStatisticsTests {
    private let host = IPAddress("1.1.1.1")!
    private func reply(_ seq: Int, _ rtt: Double) -> PingSample {
        PingSample(sequence: seq, sentAt: Date(), outcome: .reply(rtt: rtt, bytes: 64, ttl: 50, from: host))
    }
    private func timeout(_ seq: Int) -> PingSample { PingSample(sequence: seq, sentAt: Date(), outcome: .timeout) }

    @Test func emptyAndAllLost() {
        let empty = PingStatistics(samples: [PingSample]())
        #expect(empty.sent == 0 && empty.lossFraction == 0 && empty.avg == nil)
        let lost = PingStatistics(samples: [timeout(0), timeout(1)])
        #expect(lost.sent == 2 && lost.received == 0 && lost.lossFraction == 1)
        #expect(lost.min == nil && lost.max == nil && lost.stddev == nil && lost.jitter == nil)
    }

    @Test func maths() throws {
        let stats = PingStatistics(samples: [reply(0, 0.010), timeout(1), reply(2, 0.020), reply(3, 0.040), reply(4, 0.010)])
        #expect(stats.sent == 5 && stats.received == 4)
        #expect(abs(stats.lossFraction - 0.2) < 1e-12)
        #expect(stats.min == 0.010 && stats.max == 0.040)
        #expect(abs(try #require(stats.avg) - 0.02) < 1e-12)
        // population stddev of [10, 20, 40, 10] ms: mean 20, variance (100+0+400+100)/4 = 150
        #expect(abs(try #require(stats.stddev) - 150.0.squareRoot() / 1000) < 1e-12)
        // jitter over consecutive received RTTs: |20-10|, |40-20|, |10-40| -> mean 20 ms
        #expect(abs(try #require(stats.jitter) - 0.020) < 1e-12)
    }

    @Test func singleReplyHasNoJitter() {
        let stats = PingStatistics(samples: [reply(0, 0.015)])
        #expect(stats.avg == 0.015 && stats.stddev == 0 && stats.jitter == nil)
    }

    @Test func errorsCountAsSent() {
        let err = PingSample(sequence: 1, sentAt: Date(), outcome: .error(.sendFailed(errno: 1)))
        let stats = PingStatistics(samples: [reply(0, 0.01), err])
        #expect(stats.sent == 2 && stats.received == 1)
    }
}
