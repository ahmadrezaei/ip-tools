// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public struct ObservedPath: Hashable, Sendable {
    public let asns: [UInt32]                  // peer first, origin last (raw; builder cleans)
    public let collector: String
    public let peerIP: String
    /// The raw path contained AS_SET tokens that were already dropped from `asns` (DESIGN 6.3 rule 1a).
    public let hadASSet: Bool

    public init(asns: [UInt32], collector: String, peerIP: String) {
        self.init(asns: asns, collector: collector, peerIP: peerIP, hadASSet: false)
    }

    public init(asns: [UInt32], collector: String, peerIP: String, hadASSet: Bool) {
        self.asns = asns
        self.collector = collector
        self.peerIP = peerIP
        self.hadASSet = hadASSet
    }
}
