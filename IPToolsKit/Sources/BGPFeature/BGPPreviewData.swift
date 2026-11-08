// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

#if DEBUG
import BGPGraph
import CoreGraphics
import Foundation
import NetCore
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

    static func result(k: Int = 4, prefix: String = "1.1.1.0/24") -> (BGPResult, GraphLayout) {
        let graph = graph(k: k)
        let collectors = (0..<5).map { LookingGlass.Collector(id: String(format: "RRC%02d", $0), location: "Somewhere") }
        let result = BGPResult(prefix: prefix, origins: [ASHolder(asn: 13335, holder: names[13335] ?? "")], graph: graph,
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
        updateSummary()
    }

    func setPreviewPhase(_ phase: Phase, failure: BGPFailure?) {
        self.phase = phase
        self.failure = failure
    }
}

/// Hand-made routes and models for the Your route previews (no tracing, no network).
@MainActor enum BGPRoutePreviewData {
    static let names: [UInt32: String] = [
        24940: "HETZNER-AS Hetzner Online GmbH", 13335: "CLOUDFLARENET - Cloudflare, Inc.", 15169: "GOOGLE - Google LLC",
        3320: "DTAG Deutsche Telekom AG", 1299: "TWELVE99 Arelion Sweden AB",
    ]
    static let me = MyNetwork(ip: "91.107.240.242", asn: 24940, prefix: "91.107.128.0/17", name: "Hetzner Online")
    static let date = Date(timeIntervalSince1970: 1_794_000_060)

    static func context(prefixTarget: Bool = false) -> RouteContext {
        let paths = [
            ObservedPath(asns: [3320, 15169], collector: "RRC01", peerIP: "192.0.2.1"),
            ObservedPath(asns: [3320, 15169], collector: "RRC03", peerIP: "192.0.2.2"),
            ObservedPath(asns: [1299, 15169], collector: "RRC00", peerIP: "192.0.2.3"),
        ]
        return RouteContext(label: prefixTarget ? "8.8.8.0/24" : "8.8.8.8", address: prefixTarget ? nil : IPAddress("8.8.8.8"),
                            hostname: nil, prefix: "8.8.8.0/24", origins: [15169], paths: paths,
                            collectorLocations: ["RRC01": "London, United Kingdom", "RRC03": "Amsterdam, Netherlands"], snapshot: nil)
    }

    private static func hop(_ ttl: Int, _ address: String, _ kind: ChainHop.Kind, ms: Double?, reached: Bool = false) -> ChainHop {
        ChainHop(ttl: ttl, kind: kind, address: address, rtts: ms.map { [$0 / 1000, $0 / 1000 + 0.002] } ?? [], reachedTarget: reached)
    }

    static let youHops = [hop(1, "192.168.70.1", .privateAddress, ms: 3.5), hop(2, "172.16.21.1", .privateAddress, ms: 107),
                          hop(3, "10.99.7.1", .privateAddress, ms: 127)]
    static let cloudflareHops = [hop(4, "104.28.0.0", .network(13335), ms: 136), hop(5, "172.71.133.1", .network(13335), ms: 136),
                                 hop(6, "141.101.67.186", .network(13335), ms: 136), hop(7, "141.101.67.57", .network(13335), ms: 144)]
    static let googleHops = [hop(8, "108.170.255.223", .network(15169), ms: 146), hop(9, "72.14.237.93", .network(15169), ms: 145),
                             ChainHop(ttl: 10, kind: .silent),
                             hop(11, "8.8.8.8", .network(15169), ms: 144, reached: true)]

    static let you = ASChain.Node(asn: 24940, role: .you, provenance: .measured, ttls: 1...3, answeredHops: 3,
                                  rttRange: 0.003...0.133, hops: youHops)
    static let cloudflare = ASChain.Node(asn: 13335, role: .transit, provenance: .measured, ttls: 4...7, answeredHops: 4,
                                         rttRange: 0.128...0.151, hops: cloudflareHops)
    static let google = ASChain.Node(asn: 15169, role: .destination, provenance: .measured, ttls: 8...11, answeredHops: 3,
                                     rttRange: 0.139...0.152, hops: googleHops)
    static let expected = ASChain.Node(asn: 15169, role: .destination, provenance: .expected, gapBefore: true)
    private static let source = ASChain.Source.traceroute(handedOver: false, measuredAt: date)

    static let done = ASChain(nodes: [you, cloudflare, google], source: source, completion: .complete, reachedTarget: true, lastTTL: 11)
    static let handedOver = ASChain(nodes: [you, cloudflare, google], source: .traceroute(handedOver: true, measuredAt: date),
                                    completion: .complete, reachedTarget: true, lastTTL: 11)
    static let measuring = ASChain(nodes: [you, ASChain.Node(asn: 13335, role: .transit, provenance: .measured, ttls: 4...6,
                                                              answeredHops: 3, rttRange: 0.128...0.144, hops: Array(cloudflareHops.prefix(3))),
                                           expected],
                                   source: source, completion: .inProgress, reachedTarget: false, lastTTL: 6)
    static let gap = ASChain(nodes: [you, cloudflare, expected], source: source, completion: .gap, reachedTarget: false, lastTTL: 7)
    static let stitched = ASChain(
        nodes: [you, ASChain.Node(asn: 1299, role: .transit, provenance: .measured, ttls: 4...9, answeredHops: 6,
                                  rttRange: 0.01...0.04, hops: []),
                ASChain.Node(asn: 15169, role: .destination, provenance: .bgp, routeCount: 6, gapBefore: true)],
        source: source, completion: .stitched, reachedTarget: false, lastTTL: 9)
    static let noAnswer = ASChain(nodes: [ASChain.Node(asn: nil, role: .you, provenance: .measured), expected],
                                  source: source, completion: .gap, reachedTarget: false, lastTTL: nil)
    static let bgp = ASChain(
        nodes: [ASChain.Node(asn: 3320, role: .you, provenance: .bgp, routeCount: 2),
                ASChain.Node(asn: 15169, role: .destination, provenance: .bgp, routeCount: 2)],
        source: .bgp(collectors: ["RRC01", "RRC03"]), completion: .complete, reachedTarget: false)
    static let own = ASChain(nodes: [ASChain.Node(asn: 15169, role: .youAndDestination, provenance: .bgp, routeCount: 3)],
                             source: .bgp(collectors: ["RRC01"]), completion: .complete, reachedTarget: false)

    static func model(_ phase: YourRouteModel.Phase, _ chain: ASChain?, mine: MyNetwork? = me,
                      view: BGPView = .yourRoute) -> BGPMapModel {
        BGPPreviewData.model { model in
            let (result, layout) = BGPPreviewData.result(prefix: "8.8.8.0/24")
            model.targetText = "8.8.8.8"
            model.myNetwork = mine
            model.installPreview(result: result, layout: layout)
            model.view = view
            model.route.installPreview(phase: phase, chain: chain, context: context(), names: names, myNetwork: mine,
                                       hops: youHops + cloudflareHops + (8...12).map { ChainHop(ttl: $0, kind: .silent) })
        }
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

// MARK: Your route

#Preview("Route: done") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.done, BGPRoutePreviewData.done)) } }
#Preview("Route: handed over") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.done, BGPRoutePreviewData.handedOver)) } }
#Preview("Route: measuring") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.measuring(ttl: 6), BGPRoutePreviewData.measuring)) } }
#Preview("Route: locating") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.locating, nil)) } }
#Preview("Route: seen in BGP") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.done, BGPRoutePreviewData.bgp)) } }
#Preview("Route: gap") {
    NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.partial("Traceroute couldn't see past hop 7"), BGPRoutePreviewData.gap)) }
}
#Preview("Route: stitched") {
    NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.partial("Traceroute stopped in Arelion at hop 9"), BGPRoutePreviewData.stitched)) }
}
#Preview("Route: stopped") {
    NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.stopped("Stopped at hop 6"), BGPRoutePreviewData.measuring)) }
}
#Preview("Route: no answer") {
    NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.partial("No router on the way answered"), BGPRoutePreviewData.noAnswer)) }
}
#Preview("Route: own network") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.done, BGPRoutePreviewData.own)) } }
#Preview("Route: lookups off") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.lookupsOff, nil)) } }
#Preview("Route: unavailable") { NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.unavailable, nil)) } }
#Preview("Route: failed") {
    NavigationStack {
        BGPMapView(model: BGPRoutePreviewData.model(.failed("No IPv6 route — this network doesn't support IPv6."), nil))
    }
}
#Preview("Route: details") {
    ASDetailView(model: BGPRoutePreviewData.model(.done, BGPRoutePreviewData.done), routeNode: BGPRoutePreviewData.cloudflare)
}

// MARK: All routes

#Preview("All routes") {
    NavigationStack { BGPMapView(model: BGPRoutePreviewData.model(.done, BGPRoutePreviewData.done, view: .allRoutes)) }
}
#Preview("All routes, list") {
    NavigationStack {
        BGPMapView(model: BGPRoutePreviewData.model(.done, BGPRoutePreviewData.done, view: .allRoutes).withMode(.list))
    }
}
#Preview("Legend") { GraphLegendSheet(showsYou: true) }

extension BGPMapModel {
    func withMode(_ mode: DisplayMode) -> BGPMapModel {
        displayMode = mode
        return self
    }
}
#endif
