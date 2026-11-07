// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public struct ObservedPath: Hashable, Sendable {
    public let asns: [UInt32]                  // peer first, origin last (raw; builder cleans)
    public let collector: String
    public let peerIP: String
    public init(asns: [UInt32], collector: String, peerIP: String) {
        self.asns = asns
        self.collector = collector
        self.peerIP = peerIP
    }
}
