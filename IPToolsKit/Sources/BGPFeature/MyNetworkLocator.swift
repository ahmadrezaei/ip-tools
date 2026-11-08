// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import RIPEstat

public struct MyNetwork: Hashable, Sendable {
    public let ip: String
    public let asn: UInt32?
    public let prefix: String?
    public var name: String?
    public init(ip: String, asn: UInt32?, prefix: String?, name: String? = nil) {
        self.ip = ip
        self.asn = asn
        self.prefix = prefix
        self.name = name
    }
}

/// whats-my-ip -> network-info, cached per `pathGeneration` (<= 30 min).
actor MyNetworkLocator {
    init(api: any RIPEstatAPI) {}
    func current(generation: Int) async -> MyNetwork? { fatalError("TODO") }
}
