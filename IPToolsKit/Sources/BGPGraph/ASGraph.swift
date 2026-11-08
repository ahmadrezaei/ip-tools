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
    /// How an edge takes part in the overlay path (the user's own route): a known hop, or the unknown stretch
    /// between the last known network and the origin.
    public enum Overlay: Sendable { case path, unknownSegment }
    public var id: String { "\(from)>\(to)" }
    public let from: NodeID, to: NodeID
    /// Observed routes using this edge; 0 for an edge that exists only because of the overlay path.
    public let pathCount: Int
    public let kind: Kind
    public let overlay: Overlay?
    public var onHighlightPath: Bool { overlay != nil }

    public init(from: NodeID, to: NodeID, pathCount: Int, kind: Kind, overlay: Overlay? = nil) {
        self.from = from
        self.to = to
        self.pathCount = pathCount
        self.kind = kind
        self.overlay = overlay
    }
}

/// Edge and node ids on the paths through a set of ASNs (after collapsing).
public struct GraphHighlight: Equatable, Sendable {
    public var nodes: Set<NodeID>
    public var edges: Set<String>
    public init(nodes: Set<NodeID>, edges: Set<String>) {
        self.nodes = nodes
        self.edges = edges
    }
}

/// One unique cleaned AS path with how many routes and distinct collectors saw it.
public struct PathGroup: Hashable, Sendable {
    public let asns: [UInt32]
    public let count: Int
    public let collectors: Int
    public var text: String { asns.map(String.init).joined(separator: " ") }
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
    /// Nodes on the overlay path (`GraphBuildOptions.highlightPath`). They may include ASes no observed path
    /// contains; those have no path counts.
    public let highlightPathNodeIDs: Set<NodeID>

    // Derived once at construction (single pass over `cleanedPaths` and `nodes`).
    /// Paths each ASN appears on (including ASNs hidden in a "+more" bucket).
    public let pathCounts: [UInt32: Int]
    /// Paths on which each ASN is a transit hop (neither first nor last).
    public let transitCounts: [UInt32: Int]
    /// Sorted distinct collectors that saw each ASN.
    public let collectorsByASN: [UInt32: [String]]
    /// Layer of every ASN, including collapsed ones.
    public let layerByASN: [UInt32: Int]
    /// All ASNs per layer (uncollapsed), ranked by score (pathCount + transitCount) descending, ties by lower ASN.
    public let rankedByLayer: [Int: [UInt32]]
    /// ASNs that appear only on the highlight overlay (seen in no cleaned route). They stay in `layerByASN`
    /// and `rankedByLayer`; use this to tell them apart.
    public let overlayOnlyASNs: Set<UInt32>
    /// Unique cleaned paths, most frequent first.
    public let pathGroups: [PathGroup]
    private var nodeIndex: [NodeID: Int] = [:]
    private var nodeByASN: [UInt32: NodeID] = [:]

    public init(nodes: [GraphNode], edges: [GraphEdge], origins: [UInt32], totalPaths: Int,
                discardedPaths: Int, layerCount: Int, cleanedPaths: [ObservedPath],
                highlightPathNodeIDs: Set<NodeID> = []) {
        self.highlightPathNodeIDs = highlightPathNodeIDs
        self.nodes = nodes
        self.edges = edges
        self.origins = origins
        self.totalPaths = totalPaths
        self.discardedPaths = discardedPaths
        self.layerCount = layerCount
        self.cleanedPaths = cleanedPaths

        var pathCount: [UInt32: Int] = [:]
        var transit: [UInt32: Int] = [:]
        var collectors: [UInt32: Set<String>] = [:]
        var grouped: [[UInt32]: (count: Int, collectors: Set<String>)] = [:]
        for path in cleanedPaths {
            for (index, asn) in path.asns.enumerated() {
                pathCount[asn, default: 0] += 1
                if index > 0, index < path.asns.count - 1 { transit[asn, default: 0] += 1 }
                collectors[asn, default: []].insert(path.collector)
            }
            var entry = grouped[path.asns] ?? (0, [])
            entry.count += 1
            entry.collectors.insert(path.collector)
            grouped[path.asns] = entry
        }
        var layer: [UInt32: Int] = [:]
        for (i, node) in nodes.enumerated() {
            nodeIndex[node.id] = i
            switch node.id {
            case let .asn(asn):
                layer[asn] = node.layer
                nodeByASN[asn] = node.id
            case .more:
                for asn in node.collapsed {
                    layer[asn] = node.layer
                    nodeByASN[asn] = node.id
                }
            }
        }
        var ranked: [Int: [UInt32]] = [:]
        for (asn, l) in layer { ranked[l, default: []].append(asn) }
        for key in ranked.keys {
            ranked[key]?.sort { a, b in
                let sa = (pathCount[a] ?? 0) + (transit[a] ?? 0), sb = (pathCount[b] ?? 0) + (transit[b] ?? 0)
                return sa != sb ? sa > sb : a < b
            }
        }
        self.pathCounts = pathCount
        self.transitCounts = transit
        self.collectorsByASN = collectors.mapValues { $0.sorted() }
        self.layerByASN = layer
        var overlayOnly = Set<UInt32>()
        for id in highlightPathNodeIDs { if case let .asn(a) = id, pathCount[a] == nil { overlayOnly.insert(a) } }
        self.overlayOnlyASNs = overlayOnly
        self.rankedByLayer = ranked
        self.pathGroups = grouped
            .map { PathGroup(asns: $0.key, count: $0.value.count, collectors: $0.value.collectors.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.asns.lexicographicallyPrecedes($1.asns) }
    }

    public func isOverlayOnly(_ asn: UInt32) -> Bool { overlayOnlyASNs.contains(asn) }

    public func node(_ id: NodeID) -> GraphNode? { nodeIndex[id].map { nodes[$0] } }

    /// Cleaned paths that contain `asn` (collapsed or not).
    public func paths(through asn: UInt32) -> [ObservedPath] { cleanedPaths.filter { $0.asns.contains(asn) } }

    /// The node that represents `asn` in this (collapsed) graph: itself, or its layer's `.more` bucket.
    public func nodeID(for asn: UInt32) -> NodeID? { nodeByASN[asn] }

    /// Path groups containing any of `asns`.
    public func pathGroups(through asns: Set<UInt32>) -> [PathGroup] {
        pathGroups.filter { group in group.asns.contains { asns.contains($0) } }
    }

    /// Nodes and edges (after collapsing) on every path through any of `asns`.
    public func highlight(through asns: Set<UInt32>) -> GraphHighlight {
        var nodes = Set<NodeID>()
        var edges = Set<String>()
        for path in cleanedPaths where path.asns.contains(where: { asns.contains($0) }) {
            let ids = path.asns.compactMap { nodeByASN[$0] }
            nodes.formUnion(ids)
            for (a, b) in zip(ids, ids.dropFirst()) where a != b {
                edges.insert(GraphEdge(from: a, to: b, pathCount: 0, kind: .forward).id)
            }
        }
        return GraphHighlight(nodes: nodes, edges: edges)
    }

    /// Edge ids (`GraphEdge.id`, after collapsing) used by any path through `asn`.
    public func highlightedEdges(through asn: UInt32) -> Set<String> { highlight(through: [asn]).edges }

    /// All ASNs in a layer, uncollapsed, sorted by score (List "Show all").
    public func allASNs(inLayer layer: Int) -> [UInt32] { rankedByLayer[layer] ?? [] }

    /// Unique cleaned AS paths with how many routes and how many distinct collectors saw each, most frequent first.
    public func uniquePaths() -> [(asns: [UInt32], count: Int, collectors: Int)] {
        pathGroups.map { (asns: $0.asns, count: $0.count, collectors: $0.collectors) }
    }
}
