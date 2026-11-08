// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public struct RoutesSummary: Hashable, Sendable {     // DESIGN 6.12 item 2
    public let totalRoutes: Int
    public let collectorCount: Int
    public let directFraction: Double                 // paths with <= 2 ASNs / total
    public let handoffs: [UInt32]                     // <= 2 layer-1 ASNs by transitCount
    public let myASNRouteCount: Int?                  // nil when myASN unknown; 0 = not present
    public init(graph: ASGraph, collectorCount: Int, myASN: UInt32?) {
        fatalError("TODO")
    }
}
