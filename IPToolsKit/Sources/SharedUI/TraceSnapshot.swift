// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore

/// A finished trace handed from the Traceroute tab to other tools (DESIGN 12.7).
public struct TraceSnapshot: Hashable, Sendable {
    public struct Hop: Hashable, Sendable {
        public let ttl: Int
        public let address: IPAddress?                 // first responder
        public let hostname: String?
        public let asn: UInt32?
        public let rtts: [TimeInterval]
        public let reachedTarget: Bool
        public init(ttl: Int, address: IPAddress?, hostname: String?, asn: UInt32?, rtts: [TimeInterval], reachedTarget: Bool) {
            self.ttl = ttl
            self.address = address
            self.hostname = hostname
            self.asn = asn
            self.rtts = rtts
            self.reachedTarget = reachedTarget
        }
    }
    public let target: ResolvedTarget
    public let hops: [Hop]
    public let completion: TraceCompletion?
    public let finishedAt: Date
    public init(target: ResolvedTarget, hops: [Hop], completion: TraceCompletion?, finishedAt: Date) {
        self.target = target
        self.hops = hops
        self.completion = completion
        self.finishedAt = finishedAt
    }
}
