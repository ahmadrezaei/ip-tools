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
    public let origins: [UInt32]
    public let totalPaths: Int
    public let discardedPaths: Int
    public let layerCount: Int
    public let cleanedPaths: [ObservedPath]

    public init(nodes: [GraphNode], edges: [GraphEdge], origins: [UInt32], totalPaths: Int,
                discardedPaths: Int, layerCount: Int, cleanedPaths: [ObservedPath]) {
        self.nodes = nodes
        self.edges = edges
        self.origins = origins
        self.totalPaths = totalPaths
        self.discardedPaths = discardedPaths
        self.layerCount = layerCount
        self.cleanedPaths = cleanedPaths
    }

    public func node(_ id: NodeID) -> GraphNode? { nodes.first { $0.id == id } }
    /// Stub: owned by the graph agent.
    public func paths(through asn: UInt32) -> [ObservedPath] { cleanedPaths.filter { $0.asns.contains(asn) } }
    /// Stub: owned by the graph agent. Edge ids after collapsing.
    public func highlightedEdges(through asn: UInt32) -> Set<String> { [] }
    /// Stub: owned by the graph agent. Uncollapsed, sorted by score (List "Show all").
    public func allASNs(inLayer: Int) -> [UInt32] { [] }
}
