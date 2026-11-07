// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import RIPEstat

public struct HopASN: Hashable, Sendable {
    public let asn: UInt32
    public let name: String?
    public let prefix: String?
    public init(asn: UInt32, name: String?, prefix: String?) {
        self.asn = asn
        self.name = name
        self.prefix = prefix
    }
}

/// Cache + concurrency limit around `RIPEstatAPI`.
public actor ASNLookup {
    private let api: any RIPEstatAPI

    public init(api: any RIPEstatAPI) {
        self.api = api
    }

    /// Stub: UI agent implements (network-info + as-names, cached).
    public func lookup(_ address: IPAddress) async -> HopASN? { nil }

    /// Stub: UI agent implements.
    public func names(for asns: [UInt32]) async -> [UInt32: String] { [:] }
}
