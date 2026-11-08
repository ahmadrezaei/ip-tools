// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct ChainHop: Hashable, Sendable {           // neutral input; BGPGraph has no NetCore dependency
    public enum Kind: Hashable, Sendable { case silent, privateAddress, unknownNetwork, network(UInt32) }
    public let ttl: Int
    public let kind: Kind
    public let address: String?
    public let hostname: String?
    public let rtts: [TimeInterval]                    // answered probes only, seconds
    public let reachedTarget: Bool                     // echo reply from the probe target
    public init(ttl: Int, kind: Kind, address: String? = nil, hostname: String? = nil,
                rtts: [TimeInterval] = [], reachedTarget: Bool = false) {
        self.ttl = ttl
        self.kind = kind
        self.address = address
        self.hostname = hostname
        self.rtts = rtts
        self.reachedTarget = reachedTarget
    }
}

public struct ASChain: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case traceroute(handedOver: Bool, measuredAt: Date)
        case bgp(collectors: [String])
    }
    public enum Completion: Hashable, Sendable { case inProgress, complete, gap, stitched }
    public struct Node: Identifiable, Hashable, Sendable {
        public enum Role: Hashable, Sendable { case you, transit, destination, youAndDestination }
        public enum Provenance: Hashable, Sendable { case measured, bgp, expected }
        public var id: String { asn.map { "AS\($0)" } ?? "you" }     // "you" when asn == nil, else "AS<n>"
        public let asn: UInt32?                        // nil only for an unidentified You node
        public let role: Role
        public let provenance: Provenance
        public let ttls: ClosedRange<Int>?             // measured nodes
        public let answeredHops: Int
        public let rttRange: ClosedRange<TimeInterval>?
        public let hops: [ChainHop]                    // the hops inside this node
        public let routeCount: Int?                    // .bgp nodes
        public let gapBefore: Bool                     // draw the "?" gap before this node
        public init(asn: UInt32?, role: Role, provenance: Provenance, ttls: ClosedRange<Int>? = nil,
                    answeredHops: Int = 0, rttRange: ClosedRange<TimeInterval>? = nil, hops: [ChainHop] = [],
                    routeCount: Int? = nil, gapBefore: Bool = false) {
            self.asn = asn
            self.role = role
            self.provenance = provenance
            self.ttls = ttls
            self.answeredHops = answeredHops
            self.rttRange = rttRange
            self.hops = hops
            self.routeCount = routeCount
            self.gapBefore = gapBefore
        }
    }
    public let nodes: [Node]
    public let source: Source
    public let completion: Completion
    public let reachedTarget: Bool
    public let lastTTL: Int?
    public let skippedHops: Int
    public var asnSequence: [UInt32] { nodes.compactMap(\.asn) }
    public init(nodes: [Node], source: Source, completion: Completion, reachedTarget: Bool,
                lastTTL: Int? = nil, skippedHops: Int = 0) {
        self.nodes = nodes
        self.source = source
        self.completion = completion
        self.reachedTarget = reachedTarget
        self.lastTTL = lastTTL
        self.skippedHops = skippedHops
    }
}
