// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import CoreGraphics

/// Columnar layout of an `ASGraph`. Rules: DESIGN section 6.4. Deterministic and overlap-free.
///
/// Output conventions:
/// - `frames` has every node of the graph; the origin column is the rightmost one.
/// - `edges` are sorted by ascending `pathCount` (draw in this order so thick edges sit on top).
/// - `columnHeaders` run left to right (highest layer first, origin last); `layer` 0 is the "ORIGIN" caption.
public enum LayeredLayout {
    public static func layout(_ graph: ASGraph, metrics: LayoutMetrics = .init()) -> GraphLayout {
        guard !graph.nodes.isEmpty, graph.layerCount > 0 else {
            return GraphLayout(size: .zero, frames: [:], edges: [], columnHeaders: [])
        }
        let maxLayer = graph.layerCount - 1
        let order = columnOrder(graph, maxLayer: maxLayer)

        let nodeW = metrics.nodeSize.width, nodeH = metrics.nodeSize.height
        let rowPitch = nodeH + metrics.rowSpacing
        let tallest = order.values.map(\.count).max() ?? 0
        let H = CGFloat(tallest) * nodeH + CGFloat(max(0, tallest - 1)) * metrics.rowSpacing
        let L = CGFloat(maxLayer)

        var frames: [NodeID: CGRect] = [:]
        var headers: [(layer: Int, centerX: CGFloat)] = []
        for layer in stride(from: maxLayer, through: 0, by: -1) {
            let x = metrics.padding + CGFloat(maxLayer - layer) * (nodeW + metrics.columnSpacing)
            headers.append((layer, x + nodeW / 2))
            let column = order[layer] ?? []
            let columnHeight = CGFloat(column.count) * nodeH + CGFloat(max(0, column.count - 1)) * metrics.rowSpacing
            let top = metrics.padding + metrics.headerHeight + (H - columnHeight) / 2
            for (i, id) in column.enumerated() {
                frames[id] = CGRect(x: x, y: top + CGFloat(i) * rowPitch, width: nodeW, height: nodeH)
            }
        }
        let size = CGSize(width: metrics.padding * 2 + (L + 1) * nodeW + L * metrics.columnSpacing,
                          height: metrics.padding * 2 + metrics.headerHeight + H)

        let total = max(1, graph.totalPaths)
        let geometry: [EdgeGeometry] = graph.edges.compactMap { edge -> (Int, EdgeGeometry)? in
            guard let f = frames[edge.from], let t = frames[edge.to] else { return nil }
            let width = 1.5 + 6 * CGFloat((Double(edge.pathCount) / Double(total)).squareRoot())
            let start: CGPoint, end: CGPoint, c1: CGPoint, c2: CGPoint
            switch edge.kind {
            case .forward:
                start = CGPoint(x: f.maxX, y: f.midY)
                end = CGPoint(x: t.minX, y: t.midY)
                let mx = (start.x + end.x) / 2
                c1 = CGPoint(x: mx, y: start.y)
                c2 = CGPoint(x: mx, y: end.y)
            case .lateral, .backward:
                start = CGPoint(x: f.minX, y: f.midY)
                end = CGPoint(x: t.minX, y: t.midY)
                let pull = min(45, 20 + abs(end.y - start.y) * 0.25)
                c1 = CGPoint(x: start.x - pull, y: start.y)
                c2 = CGPoint(x: end.x - pull, y: end.y)
            }
            return (edge.pathCount, EdgeGeometry(id: edge.id, start: start, control1: c1, control2: c2, end: end,
                                                 lineWidth: width, kind: edge.kind))
        }.sorted { a, b in
            a.0 != b.0 ? a.0 < b.0 : a.1.id < b.1.id
        }.map(\.1)
        return GraphLayout(size: size, frames: frames, edges: geometry, columnHeaders: headers)
    }

    // MARK: Ordering

    /// Top-to-bottom node order per layer: barycentre sweep from the origin outward, then one refinement pass.
    static func columnOrder(_ graph: ASGraph, maxLayer: Int) -> [Int: [NodeID]] {
        var byLayer: [Int: [GraphNode]] = [:]
        for node in graph.nodes { byLayer[node.layer, default: []].append(node) }
        func score(_ n: GraphNode) -> Int { n.pathCount + n.transitCount }
        func asnValue(_ id: NodeID) -> UInt32 {
            if case .asn(let a) = id { return a }
            return UInt32.max
        }
        func isMore(_ id: NodeID) -> Bool {
            if case .more = id { return true }
            return false
        }
        /// Tie-break: higher score, then lower ASN.
        func tieBreak(_ a: GraphNode, _ b: GraphNode) -> Bool {
            score(a) != score(b) ? score(a) > score(b) : asnValue(a.id) < asnValue(b.id)
        }

        let forward = graph.edges.filter { $0.kind == .forward }
        var targets: [NodeID: [(NodeID, Int)]] = [:]     // source -> (target, weight)
        var sources: [NodeID: [(NodeID, Int)]] = [:]     // target -> (source, weight)
        for e in forward {
            targets[e.from, default: []].append((e.to, e.pathCount))
            sources[e.to, default: []].append((e.from, e.pathCount))
        }

        /// Orders `nodes` by weighted mean index of `links` in `reference` (ties: tieBreak). Unlinked nodes use
        /// `fallback`. `.more` is always last.
        func sorted(_ nodes: [GraphNode], links: [NodeID: [(NodeID, Int)]], reference: [NodeID],
                    fallback: (GraphNode) -> Double) -> [NodeID] {
            var index: [NodeID: Int] = [:]
            for (i, id) in reference.enumerated() { index[id] = i }
            func bary(_ n: GraphNode) -> Double {
                var sum = 0.0, weight = 0.0
                for (other, w) in links[n.id] ?? [] {
                    guard let i = index[other] else { continue }
                    sum += Double(i) * Double(w)
                    weight += Double(w)
                }
                return weight > 0 ? sum / weight : fallback(n)
            }
            let keyed = nodes.map { ($0, bary($0)) }
            let regular = keyed.filter { !isMore($0.0.id) }.sorted { a, b in
                a.1 != b.1 ? a.1 < b.1 : tieBreak(a.0, b.0)
            }
            let more = keyed.filter { isMore($0.0.id) }.map(\.0.id)
            return regular.map(\.0.id) + more
        }

        var order: [Int: [NodeID]] = [:]
        // Layer 0: origins by pathCount descending.
        order[0] = (byLayer[0] ?? []).sorted { a, b in
            a.pathCount != b.pathCount ? a.pathCount > b.pathCount : asnValue(a.id) < asnValue(b.id)
        }.map(\.id)

        if maxLayer >= 1 {
            for k in 1...maxLayer {
                order[k] = sorted(byLayer[k] ?? [], links: targets, reference: order[k - 1] ?? []) { _ in
                    Double.greatestFiniteMagnitude
                }
            }
        }

        // One refinement pass from max-1 down to 1 using incoming forward sources in layer k+1.
        if maxLayer >= 2 {
            for k in stride(from: maxLayer - 1, through: 1, by: -1) {
                let current = order[k] ?? []
                var currentIndex: [NodeID: Int] = [:]
                for (i, id) in current.enumerated() { currentIndex[id] = i }
                let candidate = sorted(byLayer[k] ?? [], links: sources, reference: order[k + 1] ?? []) {
                    Double(currentIndex[$0.id] ?? 0)
                }
                guard candidate != current else { continue }
                var trial = order
                trial[k] = candidate
                if crossings(forward, order: trial, maxLayer: maxLayer) <= crossings(forward, order: order, maxLayer: maxLayer) {
                    order = trial
                }
            }
        }
        return order
    }

    /// Number of crossing pairs among forward edges between adjacent columns.
    static func crossings(_ forward: [GraphEdge], order: [Int: [NodeID]], maxLayer: Int) -> Int {
        var position: [NodeID: Int] = [:]
        for ids in order.values { for (i, id) in ids.enumerated() { position[id] = i } }
        var layerOf: [NodeID: Int] = [:]
        for (l, ids) in order { for id in ids { layerOf[id] = l } }
        var byTargetLayer: [Int: [(Int, Int)]] = [:]
        for e in forward {
            guard let s = position[e.from], let t = position[e.to], let l = layerOf[e.to] else { continue }
            byTargetLayer[l, default: []].append((s, t))
        }
        var count = 0
        for pairs in byTargetLayer.values {
            for i in 0..<pairs.count {
                for j in (i + 1)..<max(i + 1, pairs.count) {
                    let (s1, t1) = pairs[i], (s2, t2) = pairs[j]
                    if (s1 - s2) * (t1 - t2) < 0 { count += 1 }
                }
            }
        }
        return count
    }
}
