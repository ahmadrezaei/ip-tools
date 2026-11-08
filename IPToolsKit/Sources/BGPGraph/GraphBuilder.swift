// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public struct GraphBuildOptions: Hashable, Sendable {
    public var maxNodesPerLayer: Int = 6       // 6 / 12 / 30
    public var pinned: Set<UInt32> = []        // never folded into "+N more" (DESIGN 6.12 item 4)
    public init(maxNodesPerLayer: Int = 6, pinned: Set<UInt32> = []) {
        self.maxNodesPerLayer = maxNodesPerLayer
        self.pinned = pinned
    }
}

/// Builds the layered AS graph from observed paths. Rules: DESIGN section 6.3. Deterministic: every ordering
/// is fully specified (no dependence on dictionary iteration order).
public enum GraphBuilder {
    public static func build(from paths: [ObservedPath], options: GraphBuildOptions = .init()) -> ASGraph {
        let k = max(1, options.maxNodesPerLayer)

        // 1. Clean each path.
        var cleaned: [ObservedPath] = []
        var discarded = 0
        var asSetPaths = 0
        for path in paths {
            var asns: [UInt32] = []
            for asn in path.asns where asns.last != asn { asns.append(asn) }       // 1b: collapse prepending
            guard !asns.isEmpty, Set(asns).count == asns.count else {             // 1c, 1d
                discarded += 1
                continue
            }
            if path.hadASSet { asSetPaths += 1 }
            cleaned.append(ObservedPath(asns: asns, collector: path.collector, peerIP: path.peerIP,
                                        hadASSet: path.hadASSet))
        }
        guard !cleaned.isEmpty else {
            var empty = ASGraph(nodes: [], edges: [], origins: [], totalPaths: 0, discardedPaths: discarded,
                                layerCount: 0, cleanedPaths: [])
            empty.asSetPaths = 0
            return empty
        }

        // 2. Origins (most frequent first, ties by lower ASN).
        var originVotes: [UInt32: Int] = [:]
        for p in cleaned { originVotes[p.asns.last!, default: 0] += 1 }
        let origins = originVotes.keys.sorted {
            originVotes[$0]! != originVotes[$1]! ? originVotes[$0]! > originVotes[$1]! : $0 < $1
        }

        // 3. Counts per AS.
        var pathCount: [UInt32: Int] = [:]
        var transitCount: [UInt32: Int] = [:]
        var isPeer: Set<UInt32> = []
        for p in cleaned {
            isPeer.insert(p.asns[0])
            for (i, asn) in p.asns.enumerated() {
                pathCount[asn, default: 0] += 1
                if i != 0 && i != p.asns.count - 1 { transitCount[asn, default: 0] += 1 }
            }
        }

        // 4. Directed edges toward the origin.
        struct Pair: Hashable { let from: UInt32; let to: UInt32 }
        var edgeCount: [Pair: Int] = [:]
        var predecessors: [UInt32: Set<UInt32>] = [:]       // to -> {from}
        for p in cleaned {
            for (a, b) in zip(p.asns, p.asns.dropFirst()) {
                edgeCount[Pair(from: a, to: b), default: 0] += 1
                predecessors[b, default: []].insert(a)
            }
        }

        // 5. Layers: BFS from the origins over reversed edges.
        var layer: [UInt32: Int] = [:]
        var frontier = origins
        for o in origins { layer[o] = 0 }
        var depth = 0
        while !frontier.isEmpty {
            depth += 1
            var next: [UInt32] = []
            for asn in frontier {
                for pred in (predecessors[asn] ?? []).sorted() where layer[pred] == nil {
                    layer[pred] = depth
                    next.append(pred)
                }
            }
            frontier = next
        }
        let maxLayer = layer.values.max() ?? 0

        // 6. Rank within each layer.
        func score(_ a: UInt32) -> Int { pathCount[a, default: 0] + transitCount[a, default: 0] }
        var ranked: [Int: [UInt32]] = [:]
        for (asn, l) in layer { ranked[l, default: []].append(asn) }
        for l in ranked.keys {
            ranked[l]!.sort { score($0) != score($1) ? score($0) > score($1) : $0 < $1 }
        }

        // 7. Collapse each non-origin layer to the top K plus a `.more` bucket.
        var nodeOf: [UInt32: NodeID] = [:]
        var nodes: [GraphNode] = []
        for l in 0...maxLayer {
            let all = ranked[l] ?? []
            // Origin layer: sorted by pathCount (descending), never collapsed.
            let ordered = l == 0
                ? all.sorted { pathCount[$0]! != pathCount[$1]! ? pathCount[$0]! > pathCount[$1]! : $0 < $1 }
                : all
            // Pinned ASes (DESIGN 6.12 item 4) that fall beyond the top K are kept as extra nodes after the top K
            // and before the bucket. They never take a top-K slot and are never folded.
            var keep = l == 0 ? ordered : Array(ordered.prefix(k))
            var rest = l == 0 ? [] : Array(ordered.dropFirst(k))
            if !options.pinned.isEmpty, !rest.isEmpty {
                keep += rest.filter { options.pinned.contains($0) }
                rest = rest.filter { !options.pinned.contains($0) }
            }
            for asn in keep {
                nodeOf[asn] = .asn(asn)
                nodes.append(GraphNode(id: .asn(asn), layer: l, pathCount: pathCount[asn]!,
                                       transitCount: transitCount[asn, default: 0], isOrigin: l == 0,
                                       isPeer: isPeer.contains(asn), collapsed: []))
            }
            if !rest.isEmpty {
                let id = NodeID.more(layer: l)
                for asn in rest { nodeOf[asn] = id }
                nodes.append(GraphNode(id: id, layer: l,
                                       pathCount: rest.reduce(0) { $0 + pathCount[$1]! },
                                       transitCount: rest.reduce(0) { $0 + transitCount[$1, default: 0] },
                                       isOrigin: false, isPeer: rest.contains { isPeer.contains($0) },
                                       collapsed: rest))
            }
        }
        let layerOfNode: [NodeID: Int] = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.layer) })

        // Edges: re-pointed to buckets, parallel edges merged, self-loops dropped.
        struct NodePair: Hashable { let from: NodeID; let to: NodeID }
        var merged: [NodePair: Int] = [:]
        for (pair, count) in edgeCount {
            let from = nodeOf[pair.from]!, to = nodeOf[pair.to]!
            if from == to { continue }
            merged[NodePair(from: from, to: to), default: 0] += count
        }
        func sortKey(_ id: NodeID) -> (Int, UInt32) {
            switch id {
            case .asn(let a): return (0, a)
            case .more(let l): return (1, UInt32(l))
            }
        }
        let edges: [GraphEdge] = merged.map { pair, count in
            let lf = layerOfNode[pair.from]!, lt = layerOfNode[pair.to]!
            let kind: GraphEdge.Kind = lf == lt + 1 ? .forward : (lf == lt ? .lateral : .backward)
            return GraphEdge(from: pair.from, to: pair.to, pathCount: count, kind: kind)
        }.sorted { a, b in
            if a.pathCount != b.pathCount { return a.pathCount > b.pathCount }
            let fa = sortKey(a.from), fb = sortKey(b.from)
            if fa != fb { return fa < fb }
            return sortKey(a.to) < sortKey(b.to)
        }

        // 8. Output.
        var graph = ASGraph(nodes: nodes, edges: edges, origins: origins, totalPaths: cleaned.count,
                            discardedPaths: discarded, layerCount: maxLayer + 1, cleanedPaths: cleaned)
        graph.asSetPaths = asSetPaths
        return graph
    }
}
