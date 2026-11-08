// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public struct RoutesSummary: Hashable, Sendable {     // DESIGN 6.12 item 2
    public let totalRoutes: Int
    public let collectorCount: Int
    public let directFraction: Double                 // paths with <= 2 ASNs / total
    public let handoffs: [UInt32]                     // <= 2 layer-1 ASNs by transitCount
    public let myASNRouteCount: Int?                  // nil when myASN unknown; 0 = not present
    public init(graph: ASGraph, collectorCount: Int, myASN: UInt32?) {
        let total = graph.cleanedPaths.count
        totalRoutes = total
        self.collectorCount = collectorCount
        let direct = graph.cleanedPaths.reduce(0) { $0 + ($1.asns.count <= 2 ? 1 : 0) }
        directFraction = total == 0 ? 0 : Double(direct) / Double(total)

        // Layer-1 ASes (including ones folded into "+N more") that carry traffic as transit, most transit first.
        // Ties go to the higher score (pathCount + transitCount), then the lower ASN.
        func score(_ asn: UInt32) -> Int { (graph.pathCounts[asn] ?? 0) + (graph.transitCounts[asn] ?? 0) }
        let candidates = (graph.rankedByLayer[1] ?? []).filter { (graph.transitCounts[$0] ?? 0) > 0 }
        handoffs = Array(candidates.sorted { a, b in
            let ta = graph.transitCounts[a] ?? 0, tb = graph.transitCounts[b] ?? 0
            if ta != tb { return ta > tb }
            if score(a) != score(b) { return score(a) > score(b) }
            return a < b
        }.prefix(2))

        myASNRouteCount = myASN.map { graph.pathCounts[$0] ?? 0 }
    }
}
