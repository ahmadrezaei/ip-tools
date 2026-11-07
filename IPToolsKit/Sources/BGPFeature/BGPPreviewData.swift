// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

#if DEBUG
import BGPGraph
import CoreGraphics
import Foundation
import RIPEstat
import SharedUI
import SwiftUI

/// Hand-made graph, layout and models for previews and tests. It does not depend on `GraphBuilder` /
/// `LayeredLayout`, so the UI can be exercised on its own.
@MainActor enum BGPPreviewData {
    static let names: [UInt32: String] = MockRIPEstat.sampleNames.merging([
        64500: "EXAMPLE-ONE Example One Networks", 64501: "EXAMPLE-TWO Example Two Ltd",
        64502: "EXAMPLE-THREE Example Three GmbH", 64503: "EXAMPLE-FOUR Example Four S.A.",
    ]) { a, _ in a }

    static let paths: [ObservedPath] = {
        let routes: [([UInt32], Int)] = [
            ([6939, 13335], 9), ([174, 13335], 7), ([12389, 174, 13335], 6), ([20940, 3356, 13335], 5),
            ([15169, 3356, 13335], 4), ([1273, 1299, 13335], 4), ([3320, 1299, 13335], 3),
            ([7018, 2914, 13335], 3), ([64500, 3257, 13335], 2), ([64501, 6453, 13335], 2),
            ([64502, 6453, 13335], 1), ([64503, 6453, 13335], 1), ([64502, 3257, 13335], 1),
        ]
        var result: [ObservedPath] = []
        var n = 0
        for (asns, count) in routes {
            for _ in 0..<count {
                n += 1
                result.append(ObservedPath(asns: asns, collector: String(format: "RRC%02d", n % 5), peerIP: "192.0.2.\(n)"))
            }
        }
        return result
    }()

    /// A small graph following the builder's rules (layers by distance from the origin, top-K collapse).
    static func graph(paths: [ObservedPath] = paths, k: Int = 4) -> ASGraph {
        var layer: [UInt32: Int] = [:]
        var count: [UInt32: Int] = [:], transit: [UInt32: Int] = [:], peers = Set<UInt32>()
        for path in paths {
            peers.insert(path.asns[0])
            for (i, asn) in path.asns.enumerated() {
                count[asn, default: 0] += 1
                if i > 0, i < path.asns.count - 1 { transit[asn, default: 0] += 1 }
                layer[asn] = min(layer[asn] ?? .max, path.asns.count - 1 - i)
            }
        }
        let maxLayer = layer.values.max() ?? 0
        var display: [UInt32: NodeID] = [:]
        var nodes: [GraphNode] = []
        for l in 0...maxLayer {
            let members = layer.filter { $0.value == l }.keys.sorted {
                let a = count[$0, default: 0] + transit[$0, default: 0], b = count[$1, default: 0] + transit[$1, default: 0]
                return a != b ? a > b : $0 < $1
            }
            let keep = l == 0 ? members : Array(members.prefix(k))
            let rest = l == 0 ? [] : Array(members.dropFirst(k))
            for asn in keep {
                display[asn] = .asn(asn)
                nodes.append(GraphNode(id: .asn(asn), layer: l, pathCount: count[asn] ?? 0, transitCount: transit[asn] ?? 0,
                                       isOrigin: l == 0, isPeer: peers.contains(asn), collapsed: []))
            }
            if !rest.isEmpty {
                for asn in rest { display[asn] = .more(layer: l) }
                nodes.append(GraphNode(id: .more(layer: l), layer: l, pathCount: rest.reduce(0) { $0 + (count[$1] ?? 0) },
                                       transitCount: 0, isOrigin: false, isPeer: false, collapsed: rest))
            }
        }
        var edgeCounts: [String: (GraphEdge, Int)] = [:]
        for path in paths {
            for (a, b) in zip(path.asns, path.asns.dropFirst()) {
                guard let from = display[a], let to = display[b], from != to else { continue }
                let id = GraphEdge(from: from, to: to, pathCount: 0, kind: .forward).id
                edgeCounts[id] = (GraphEdge(from: from, to: to, pathCount: 0, kind: .forward), (edgeCounts[id]?.1 ?? 0) + 1)
            }
        }
        let edges = edgeCounts.values.map { GraphEdge(from: $0.0.from, to: $0.0.to, pathCount: $0.1, kind: .forward) }
        return ASGraph(nodes: nodes, edges: edges, origins: [13335], totalPaths: paths.count, discardedPaths: 0,
                       layerCount: maxLayer + 1, cleanedPaths: paths)
    }

    /// Simple columns-by-layer layout with the spec's metrics and curves.
    static func layout(_ graph: ASGraph, metrics m: LayoutMetrics = .init()) -> GraphLayout {
        let maxLayer = graph.layerCount - 1
        let columns = (0...maxLayer).map { l in graph.nodes.filter { $0.layer == l } }
        let tallest = columns.map(\.count).max() ?? 1
        let columnHeight = CGFloat(tallest) * m.nodeSize.height + CGFloat(max(tallest - 1, 0)) * m.rowSpacing
        var frames: [NodeID: CGRect] = [:]
        for (l, nodes) in columns.enumerated() {
            let x = m.padding + CGFloat(maxLayer - l) * (m.nodeSize.width + m.columnSpacing)
            let h = CGFloat(nodes.count) * m.nodeSize.height + CGFloat(max(nodes.count - 1, 0)) * m.rowSpacing
            let top = m.padding + m.headerHeight + (columnHeight - h) / 2
            for (i, node) in nodes.enumerated() {
                frames[node.id] = CGRect(x: x, y: top + CGFloat(i) * (m.nodeSize.height + m.rowSpacing),
                                         width: m.nodeSize.width, height: m.nodeSize.height)
            }
        }
        let edges = graph.edges.compactMap { edge -> EdgeGeometry? in
            guard let a = frames[edge.from], let b = frames[edge.to] else { return nil }
            let start = CGPoint(x: a.maxX, y: a.midY), end = CGPoint(x: b.minX, y: b.midY)
            let mx = (start.x + end.x) / 2
            return EdgeGeometry(id: edge.id, start: start, control1: CGPoint(x: mx, y: start.y), control2: CGPoint(x: mx, y: end.y),
                                end: end, lineWidth: 1.5 + 6 * (Double(edge.pathCount) / Double(max(graph.totalPaths, 1))).squareRoot(),
                                kind: edge.kind)
        }
        let size = CGSize(width: m.padding * 2 + CGFloat(maxLayer + 1) * m.nodeSize.width + CGFloat(maxLayer) * m.columnSpacing,
                          height: m.padding * 2 + m.headerHeight + columnHeight)
        let headers = (0...maxLayer).map { l in
            (layer: l, centerX: m.padding + CGFloat(maxLayer - l) * (m.nodeSize.width + m.columnSpacing) + m.nodeSize.width / 2)
        }
        return GraphLayout(size: size, frames: frames, edges: edges, columnHeaders: headers)
    }

    static func result(k: Int = 4) -> (BGPResult, GraphLayout) {
        let graph = graph(k: k)
        let collectors = (0..<5).map { LookingGlass.Collector(id: String(format: "RRC%02d", $0), location: "Somewhere") }
        let result = BGPResult(prefix: "1.1.1.0/24", origins: [ASHolder(asn: 13335, holder: names[13335] ?? "")], graph: graph,
                               collectors: collectors, visibility: .init(seeing: 319, total: 319), latestTime: Date(), names: names)
        return (result, layout(graph))
    }

    static func model(_ configure: (BGPMapModel) -> Void = { _ in }) -> BGPMapModel {
        let defaults = UserDefaults(suiteName: "com.ahmadrezaei.iptools.bgp-preview") ?? .standard
        let model = BGPMapModel(api: MockRIPEstat(fixtureBundle: .main, latency: .seconds(3600)),
                                recents: RecentsStore(defaults: defaults), router: AppRouter(selectedTool: .bgp))
        configure(model)
        return model
    }

    static func loadedModel(selection: NodeID? = nil, mode: BGPMapModel.DisplayMode = .graph) -> BGPMapModel {
        model { model in
            let (result, layout) = result()
            model.targetText = "1.1.1.1"
            model.installPreview(result: result, layout: layout)
            model.displayMode = mode
            model.selection = selection
        }
    }
}

extension BGPMapModel {
    func installPreview(result: BGPResult, layout: GraphLayout) {
        install(result: result, layout: layout)
        setPreviewPhase(.loaded, failure: nil)
    }

    func setPreviewPhase(_ phase: Phase, failure: BGPFailure?) {
        self.phase = phase
        self.failure = failure
    }
}

#Preview("Graph") {
    NavigationStack { BGPMapView(model: BGPPreviewData.loadedModel()) }
}

#Preview("Graph, selected") {
    NavigationStack { BGPMapView(model: BGPPreviewData.loadedModel(selection: .asn(3356))) }
}

#Preview("List") {
    NavigationStack { BGPMapView(model: BGPPreviewData.loadedModel(mode: .list)) }
}

#Preview("Loading") {
    NavigationStack {
        BGPMapView(model: BGPPreviewData.model { $0.setPreviewPhase(.loading("Fetching routes from RIPEstat…"), failure: nil) })
    }
}

#Preview("Error") {
    NavigationStack {
        BGPMapView(model: BGPPreviewData.model {
            $0.setPreviewPhase(.failed("RIPEstat is busy. Try again in a moment."), failure: .busyFailure)
        })
    }
}

#Preview("Not routed") {
    NavigationStack {
        BGPMapView(model: BGPPreviewData.model {
            $0.targetText = "10.0.0.0/8"
            $0.map()
        })
    }
}

#Preview("Empty") {
    NavigationStack { BGPMapView(model: BGPPreviewData.model()) }
}

#Preview("Prefix picker") {
    PrefixPickerView(asn: 13335, holder: BGPPreviewData.names[13335], prefixes: (0..<40).map { "104.16.\($0).0/24" } + ["2606:4700::/32"],
                     onPick: { _ in })
}

#Preview("AS details") {
    ASDetailView(model: BGPPreviewData.loadedModel(selection: .asn(3356)), id: .asn(3356))
}
#endif
