// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public enum NodeID: Hashable, Sendable { case asn(UInt32), more(layer: Int) }

public struct GraphNode: Identifiable, Hashable, Sendable {
    public enum Role: Sendable { case origin, transit, peer }
    public let id: NodeID
    public let layer: Int
    public let pathCount: Int
    public let transitCount: Int
    public let isOrigin: Bool
    public let isPeer: Bool
    public let collapsed: [UInt32]             // non-empty only for .more
    public var role: Role { isOrigin ? .origin : (isPeer ? .peer : .transit) }

    public init(id: NodeID, layer: Int, pathCount: Int, transitCount: Int, isOrigin: Bool, isPeer: Bool, collapsed: [UInt32]) {
        self.id = id
        self.layer = layer
        self.pathCount = pathCount
        self.transitCount = transitCount
        self.isOrigin = isOrigin
        self.isPeer = isPeer
        self.collapsed = collapsed
    }
}

public struct GraphEdge: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case forward, lateral, backward }
    public var id: String { "\(from)>\(to)" }
    public let from: NodeID, to: NodeID
    public let pathCount: Int
    public let kind: Kind

    public init(from: NodeID, to: NodeID, pathCount: Int, kind: Kind) {
        self.from = from
        self.to = to
        self.pathCount = pathCount
        self.kind = kind
    }
}

public struct ASGraph: Sendable {
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    /// Origin ASNs, most frequent first (the primary origin is `origins[0]`). More than one means MOAS.
    public let origins: [UInt32]
    /// Number of valid (cleaned, kept) paths. `totalPaths + discardedPaths` is the number of input paths.
    public let totalPaths: Int
    public let discardedPaths: Int
    /// Number of layers (columns): the origin layer is 0, so the highest layer index is `layerCount - 1`.
    public let layerCount: Int
    public let cleanedPaths: [ObservedPath]
    /// Number of kept paths that had AS_SET tokens removed.
    public internal(set) var asSetPaths: Int = 0

    /// Uncollapsed ASNs per layer, ranked by score (pathCount + transitCount) descending, ties by lower ASN.
    var rankedByLayer: [Int: [UInt32]] = [:]
    var layerByASN: [UInt32: Int] = [:]
    private var nodeIndex: [NodeID: Int] = [:]

    public init(nodes: [GraphNode], edges: [GraphEdge], origins: [UInt32], totalPaths: Int,
                discardedPaths: Int, layerCount: Int, cleanedPaths: [ObservedPath]) {
        self.nodes = nodes
        self.edges = edges
        self.origins = origins
        self.totalPaths = totalPaths
        self.discardedPaths = discardedPaths
        self.layerCount = layerCount
        self.cleanedPaths = cleanedPaths
        for (i, node) in nodes.enumerated() { nodeIndex[node.id] = i }
    }

    public func node(_ id: NodeID) -> GraphNode? { nodeIndex[id].map { nodes[$0] } }

    /// Cleaned paths that contain `asn` (collapsed or not).
    public func paths(through asn: UInt32) -> [ObservedPath] { cleanedPaths.filter { $0.asns.contains(asn) } }

    /// The node that represents `asn` in this (collapsed) graph: itself, or its layer's `.more` bucket.
    public func nodeID(for asn: UInt32) -> NodeID? {
        if nodeIndex[.asn(asn)] != nil { return .asn(asn) }
        guard let layer = layerByASN[asn], nodeIndex[.more(layer: layer)] != nil else { return nil }
        return .more(layer: layer)
    }

    /// Edge ids (`GraphEdge.id`, after collapsing) used by any path through `asn`.
    public func highlightedEdges(through asn: UInt32) -> Set<String> {
        var result: Set<String> = []
        for path in paths(through: asn) {
            let ids = path.asns.compactMap { nodeID(for: $0) }
            for (a, b) in zip(ids, ids.dropFirst()) where a != b {
                result.insert("\(a)>\(b)")
            }
        }
        return result
    }

    /// All ASNs in a layer, uncollapsed, sorted by score (List "Show all").
    public func allASNs(inLayer layer: Int) -> [UInt32] { rankedByLayer[layer] ?? [] }

    /// Unique cleaned AS paths with how many routes and how many distinct collectors saw each, most frequent first.
    public func uniquePaths() -> [(asns: [UInt32], count: Int, collectors: Int)] {
        var groups: [[UInt32]: (count: Int, collectors: Set<String>)] = [:]
        for path in cleanedPaths {
            var g = groups[path.asns] ?? (0, [])
            g.count += 1
            g.collectors.insert(path.collector)
            groups[path.asns] = g
        }
        return groups
            .map { (asns: $0.key, count: $0.value.count, collectors: $0.value.collectors.count) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.asns.lexicographicallyPrecedes(b.asns)
            }
    }
}
