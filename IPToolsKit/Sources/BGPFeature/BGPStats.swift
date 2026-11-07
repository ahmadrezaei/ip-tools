// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import RIPEstat

/// Derived numbers for one `ASGraph`, computed from its cleaned paths. The UI reads these instead of asking
/// the graph for per-AS data so that ASes hidden inside a "+more" bucket can still be described.
struct BGPStats: Sendable {
    enum Role: Sendable { case origin, transit, peer }

    struct PathGroup: Hashable, Sendable {
        let asns: [UInt32]
        let count: Int
        let collectors: Int
        var text: String { asns.map(String.init).joined(separator: " ") }
    }

    struct Summary: Sendable {
        let id: NodeID
        let asn: UInt32?
        let role: Role?
        let paths: Int
        let fraction: Double
        let hops: Int
        let collapsed: [UInt32]
    }

    let total: Int
    let pathCount: [UInt32: Int]
    let transitCount: [UInt32: Int]
    let layer: [UInt32: Int]
    let collectors: [UInt32: [String]]
    let nodeFor: [UInt32: NodeID]
    let origins: Set<UInt32>
    let groups: [PathGroup]
    let layerMembers: [Int: [UInt32]]

    init(graph: ASGraph) {
        var pathCount: [UInt32: Int] = [:]
        var transit: [UInt32: Int] = [:]
        var collectors: [UInt32: Set<String>] = [:]
        var grouped: [[UInt32]: (count: Int, collectors: Set<String>)] = [:]
        for path in graph.cleanedPaths {
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
        var nodeFor: [UInt32: NodeID] = [:]
        for node in graph.nodes {
            switch node.id {
            case let .asn(asn):
                layer[asn] = node.layer
                nodeFor[asn] = node.id
            case .more:
                for asn in node.collapsed {
                    layer[asn] = node.layer
                    nodeFor[asn] = node.id
                }
            }
        }
        let origins = Set(graph.origins)
        var members: [Int: [UInt32]] = [:]
        for (asn, l) in layer { members[l, default: []].append(asn) }
        for key in members.keys {
            members[key]?.sort { a, b in
                let sa = (pathCount[a] ?? 0) + (transit[a] ?? 0), sb = (pathCount[b] ?? 0) + (transit[b] ?? 0)
                return sa != sb ? sa > sb : a < b
            }
        }
        self.total = max(graph.totalPaths, 0)
        self.pathCount = pathCount
        self.transitCount = transit
        self.layer = layer
        self.collectors = collectors.mapValues { $0.sorted() }
        self.nodeFor = nodeFor
        self.origins = origins
        self.layerMembers = members
        self.groups = grouped.map { PathGroup(asns: $0.key, count: $0.value.count, collectors: $0.value.collectors.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.asns.lexicographicallyPrecedes($1.asns) }
    }

    func role(of asn: UInt32) -> Role {
        if origins.contains(asn) { return .origin }
        return (transitCount[asn] ?? 0) > 0 ? .transit : .peer
    }

    func summary(for id: NodeID, graph: ASGraph) -> Summary? {
        switch id {
        case let .asn(asn):
            guard let count = pathCount[asn] else { return nil }
            return Summary(id: id, asn: asn, role: role(of: asn), paths: count, fraction: fraction(count),
                           hops: layer[asn] ?? 0, collapsed: [])
        case .more:
            guard let node = graph.node(id) else { return nil }
            return Summary(id: id, asn: nil, role: nil, paths: node.pathCount, fraction: fraction(node.pathCount),
                           hops: node.layer, collapsed: node.collapsed)
        }
    }

    func fraction(_ count: Int) -> Double { total > 0 ? Double(count) / Double(total) : 0 }

    func groups(through asns: Set<UInt32>) -> [PathGroup] {
        groups.filter { group in group.asns.contains { asns.contains($0) } }
    }

    /// Edge and node ids on every path through `asns`, after collapsing.
    func highlight(through asns: Set<UInt32>, graph: ASGraph) -> BGPHighlight {
        var nodes = Set<NodeID>()
        var edges = Set<String>()
        for path in graph.cleanedPaths where path.asns.contains(where: { asns.contains($0) }) {
            let ids = path.asns.compactMap { nodeFor[$0] }
            nodes.formUnion(ids)
            for pair in zip(ids, ids.dropFirst()) where pair.0 != pair.1 {
                edges.insert(GraphEdge(from: pair.0, to: pair.1, pathCount: 0, kind: .forward).id)
            }
        }
        return BGPHighlight(nodes: nodes, edges: edges)
    }
}

struct BGPHighlight: Equatable, Sendable {
    var nodes: Set<NodeID>
    var edges: Set<String>
}

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
