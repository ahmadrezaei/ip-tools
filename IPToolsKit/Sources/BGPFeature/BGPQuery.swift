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

extension BGPResult {
    /// Origin ASNs, from the graph when it has them, otherwise from the origin lookup.
    var originASNs: [UInt32] { graph.origins.isEmpty ? origins.map(\.asn) : graph.origins }

    func holder(of asn: UInt32) -> String? {
        if let name = names[asn], !name.isEmpty { return name }
        return origins.first { $0.asn == asn }.flatMap { $0.holder.isEmpty ? nil : $0.holder }
    }
}
