// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import RIPEstat

/// Thin adapter over `ASGraph`'s precomputed counts and path grouping (the single implementation lives in
/// BGPGraph). The UI reads these instead of asking the graph per AS so that ASes hidden inside a "+more"
/// bucket can still be described.
struct BGPStats: Sendable {
    enum Role: Sendable { case origin, transit, peer }

    typealias PathGroup = BGPGraph.PathGroup

    struct Summary: Sendable {
        let id: NodeID
        let asn: UInt32?
        let role: Role?
        let paths: Int
        let fraction: Double
        let hops: Int
        let collapsed: [UInt32]
    }

    let graph: ASGraph
    private let originSet: Set<UInt32>

    init(graph: ASGraph) {
        self.graph = graph
        self.originSet = Set(graph.origins)
    }

    var total: Int { max(graph.totalPaths, 0) }
    var pathCount: [UInt32: Int] { graph.pathCounts }
    var transitCount: [UInt32: Int] { graph.transitCounts }
    var layer: [UInt32: Int] { graph.layerByASN }
    var collectors: [UInt32: [String]] { graph.collectorsByASN }
    var groups: [PathGroup] { graph.pathGroups }
    var layerMembers: [Int: [UInt32]] { graph.rankedByLayer }
    var origins: Set<UInt32> { originSet }

    func nodeFor(_ asn: UInt32) -> NodeID? { graph.nodeID(for: asn) }

    func role(of asn: UInt32) -> Role {
        if originSet.contains(asn) { return .origin }
        if graph.pathCounts[asn] == nil { return .transit }       // only on the overlay path
        return (graph.transitCounts[asn] ?? 0) > 0 ? .transit : .peer
    }

    func summary(for id: NodeID, graph: ASGraph) -> Summary? {
        switch id {
        case let .asn(asn):
            // An AS only on the overlay path (your path) is in the graph with no routes.
            guard let count = graph.pathCounts[asn] ?? (graph.node(id) == nil ? nil : 0) else { return nil }
            return Summary(id: id, asn: asn, role: role(of: asn), paths: count, fraction: fraction(count),
                           hops: graph.layerByASN[asn] ?? 0, collapsed: [])
        case .more:
            guard let node = graph.node(id) else { return nil }
            return Summary(id: id, asn: nil, role: nil, paths: node.pathCount, fraction: fraction(node.pathCount),
                           hops: node.layer, collapsed: node.collapsed)
        }
    }

    func fraction(_ count: Int) -> Double { total > 0 ? Double(count) / Double(total) : 0 }

    func groups(through asns: Set<UInt32>) -> [PathGroup] { graph.pathGroups(through: asns) }

    func highlight(through asns: Set<UInt32>) -> BGPHighlight { graph.highlight(through: asns) }
}

typealias BGPHighlight = GraphHighlight

/// Text helpers shared by the views and the export.
enum BGPText {
    static func roleName(_ role: BGPStats.Role?) -> String {
        switch role {
        case .origin: String(localized: "Origin")
        case .transit: String(localized: "Transit")
        case .peer: String(localized: "Peer")
        case nil: String(localized: "More networks")
        }
    }

    static func hops(_ hops: Int) -> String {
        switch hops {
        case 0: String(localized: "origin")
        case 1: String(localized: "1 hop from origin")
        default: String(localized: "\(hops) hops from origin")
        }
    }

    static func percent(_ fraction: Double) -> String { String(format: "%.1f%%", fraction * 100) }

    /// Holder without the leading handle ("CLOUDFLARENET - Cloudflare, Inc." -> "Cloudflare, Inc.").
    static func fullName(_ holder: String?) -> String? {
        guard var name = holder?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        if let range = name.range(of: " - ") {
            name = String(name[range.upperBound...])
        } else {
            let parts = name.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count > 1 { name = String(parts[1]) }
        }
        return name
    }

    static func shortName(_ holder: String?) -> String? {
        guard let holder, !holder.isEmpty else { return nil }
        let short = ASName.short(holder)
        return short.isEmpty ? nil : short
    }

    /// "AS 3356, Level 3 Parent, transit, 4 paths, 1 hop from origin"
    static func accessibilityLabel(for summary: BGPStats.Summary, names: [UInt32: String]) -> String {
        if let asn = summary.asn {
            var parts = ["AS \(asn)"]
            if let name = shortName(names[asn]) { parts.append(name) }
            parts.append(roleName(summary.role).lowercased())
            parts.append(String(localized: "\(summary.paths) paths"))
            parts.append(hops(summary.hops))
            return parts.joined(separator: ", ")
        }
        return [String(localized: "\(summary.collapsed.count) more networks"),
                String(localized: "\(summary.paths) paths"), hops(summary.hops)].joined(separator: ", ")
    }
}
