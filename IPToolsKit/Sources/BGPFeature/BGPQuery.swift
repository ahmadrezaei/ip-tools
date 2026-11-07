// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import NetCore
import RIPEstat

public enum BGPQuery: Hashable, Sendable { case address(IPAddress, hostname: String?), prefix(String), asn(UInt32) }

public struct BGPResult: Sendable {
    public let prefix: String
    public let origins: [ASHolder]
    public let graph: ASGraph
    public let collectors: [LookingGlass.Collector]
    public let visibility: RoutingStatus.Visibility?
    public let latestTime: Date?
    public var names: [UInt32: String]

    public init(prefix: String, origins: [ASHolder], graph: ASGraph, collectors: [LookingGlass.Collector],
                visibility: RoutingStatus.Visibility?, latestTime: Date?, names: [UInt32: String]) {
        self.prefix = prefix
        self.origins = origins
        self.graph = graph
        self.collectors = collectors
        self.visibility = visibility
        self.latestTime = latestTime
        self.names = names
    }
}
