// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct PingOptions: Codable, Hashable, Sendable {
    public var count: Int?            = 10       // nil = until stopped
    public var interval: TimeInterval = 1.0
    public var timeout: TimeInterval  = 2.0
    public var payloadSize: Int       = 56
    public static let `default` = PingOptions()
    public init() {}
}

public struct PingSample: Identifiable, Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case reply(rtt: TimeInterval, bytes: Int, ttl: Int?, from: IPAddress)   // rtt in seconds
        case timeout
        case unreachable(code: UInt8, from: IPAddress)
        case error(NetError)
    }
    public var id: Int { sequence }
    public let sequence: Int                  // 0-based, monotonically increasing
    public let sentAt: Date
    public let outcome: Outcome

    public init(sequence: Int, sentAt: Date, outcome: Outcome) {
        self.sequence = sequence
        self.sentAt = sentAt
        self.outcome = outcome
    }
}

public protocol PingService: Sendable {
    /// Emits one sample per probe as its outcome becomes known; finishes after `count` probes,
    /// or runs until the consuming Task is cancelled. Throws NetError for fatal setup/send errors.
    func ping(_ target: ResolvedTarget, options: PingOptions) -> AsyncThrowingStream<PingSample, Error>
}
