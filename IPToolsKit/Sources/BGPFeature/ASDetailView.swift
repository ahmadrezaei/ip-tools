// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SharedUI
import SwiftUI

/// Details of one AS (or a "+more" bucket). Sheet on iPhone, inspector on iPad.
struct ASDetailView: View {
    let model: BGPMapModel
    let id: NodeID?
    var routeNode: ASChain.Node?

    @State private var showAllPaths = false
    @Environment(\.openURL) private var openURL

    private static let pathLimit = 50

    init(model: BGPMapModel, id: NodeID) {
        self.model = model
        self.id = id
        self.routeNode = nil
    }

    /// A node of Your route; works for ASNs that aren't in the graph.
    init(model: BGPMapModel, routeNode: ASChain.Node) {
        self.model = model
        self.id = routeNode.asn.map { NodeID.asn($0) }
        self.routeNode = routeNode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let routeNode { OnYourRouteSection(node: routeNode, model: model) }
                if let result = model.result, let stats = model.stats, let id,
                   let summary = stats.summary(for: id, graph: result.graph) {
                    content(result: result, stats: stats, summary: summary)
                } else if let result = model.result, let asn = id?.asnValue {
                    notInGraph(asn, result: result)
                } else if routeNode == nil {
                    ContentUnavailableView("No details", systemImage: "questionmark.circle")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// An AS that no RIS route passes through (for example Cloudflare for 8.8.8.0/24).
    @ViewBuilder
    private func notInGraph(_ asn: UInt32, result: BGPResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SELECTED AS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: "AS\(asn)").font(.title2.bold()).monospacedDigit()
            if let holder = model.holder(of: asn) {
                Text(holder).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("In BGP routes to \(result.prefix)").font(.caption).foregroundStyle(.secondary)
            Text("Not in any of the \(result.graph.totalPaths) RIS routes").font(.headline)
            Text("Traceroute shows the real path; RIPE collectors only see part of the Internet.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        actions(asn)
    }

    @ViewBuilder
    private func content(result: BGPResult, stats: BGPStats, summary: BGPStats.Summary) -> some View {
        header(result: result, summary: summary)
        badges(summary: summary)
        tiles(stats: stats, summary: summary)
        if summary.asn == nil { collapsedList(result: result, stats: stats, summary: summary) }
        paths(stats: stats, summary: summary)
        if let asn = summary.asn { actions(asn) }
    }

    private func header(result: BGPResult, summary: BGPStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SELECTED AS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let asn = summary.asn {
                Text(verbatim: "AS\(asn)").font(.title2.bold()).monospacedDigit()
                if let holder = result.holder(of: asn) {
                    Text(holder).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } else {
                Text("+\(summary.collapsed.count) more").font(.title2.bold())
                Text("Networks grouped to keep the graph readable").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func badges(summary: BGPStats.Summary) -> some View {
        HStack(spacing: 6) {
            if summary.asn != nil { badge(BGPText.roleName(summary.role), tint: summary.role == .origin ? .accentColor : .secondary) }
            badge(BGPText.hops(summary.hops))
        }
    }

    private func badge(_ text: String, tint: Color = .secondary) -> some View {
        Text(text).font(.caption.weight(.medium))
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.15)))
    }

    private func tiles(stats: BGPStats, summary: BGPStats.Summary) -> some View {
        let collectors: [String]
        if let asn = summary.asn {
            collectors = stats.collectors[asn] ?? []
        } else {
            collectors = Array(Set(summary.collapsed.flatMap { stats.collectors[$0] ?? [] })).sorted()
        }
        return HStack(alignment: .top, spacing: 10) {
            tile(title: String(localized: "Paths through"), value: "\(summary.paths)",
                 detail: String(localized: "\(BGPText.percent(summary.fraction)) of \(stats.total)"))
            tile(title: String(localized: "Collectors"), value: "\(collectors.count)",
                 detail: collectors.prefix(3).joined(separator: ", ") + (collectors.count > 3 ? "…" : ""))
        }
    }

    private func tile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private func collapsedList(result: BGPResult, stats: BGPStats, summary: BGPStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Networks in this group").font(.headline)
            ForEach(summary.collapsed, id: \.self) { asn in
                Button { model.promote(asn) } label: {
                    HStack {
                        Text(verbatim: "AS\(asn)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(BGPText.shortName(result.holder(of: asn)) ?? "")
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text("\(stats.pathCount[asn] ?? 0) paths").font(.footnote).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows this network in the graph"))
                Divider()
            }
        }
    }

    private func paths(stats: BGPStats, summary: BGPStats.Summary) -> some View {
        let asns: Set<UInt32> = summary.asn.map { [$0] } ?? Set(summary.collapsed)
        let groups = stats.groups(through: asns)
        let shown = showAllPaths ? groups : Array(groups.prefix(Self.pathLimit))
        return VStack(alignment: .leading, spacing: 6) {
            Text(summary.asn.map { String(localized: "Paths through AS\(String($0))") } ?? String(localized: "Paths through this group")).font(.headline)
            ForEach(shown, id: \.self) { group in
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.pathText(group.asns, highlighting: asns))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Text("×\(group.count)").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if groups.count > Self.pathLimit, !showAllPaths {
                Button("Show all \(groups.count)") { showAllPaths = true }.font(.footnote)
            }
        }
    }

    static func pathText(_ path: [UInt32], highlighting asns: Set<UInt32>) -> AttributedString {
        var text = AttributedString()
        for (index, asn) in path.enumerated() {
            var token = AttributedString(index == 0 ? String(asn) : " " + String(asn))
            if asns.contains(asn) {
                token.foregroundColor = .accentColor
                token.inlinePresentationIntent = .stronglyEmphasized
            }
            text += token
        }
        return text
    }

    private func actions(_ asn: UInt32) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.mapASN(asn) } label: {
                Label("Map prefixes of AS\(String(asn))", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            HStack {
                Button { Clipboard.copy("AS\(asn)") } label: {
                    Label("Copy ASN", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                Button {
                    if let url = URL(string: "https://stat.ripe.net/AS\(asn)") { openURL(url) }
                } label: {
                    Label("Open in RIPEstat", systemImage: "safari").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

/// "On your route": role, hops, RTT range and the hop rows inside the network (DESIGN 6.11.8).
struct OnYourRouteSection: View {
    let node: ASChain.Node
    let model: BGPMapModel

    private var route: YourRouteModel { model.route }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On your route").font(.headline)
            if let asn = node.asn {
                Text(verbatim: "AS\(asn)").font(.title2.bold()).monospacedDigit()
                if let name = route.fullName(asn) ?? model.holder(of: asn) {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Text("Your network").font(.title2.bold())
            }
            Text(roleText).font(.subheadline.weight(.medium))
            HStack(alignment: .top, spacing: 10) {
                if let hops = RouteText.hops(node.ttls) {
                    tile(String(localized: "Hops"), hops, detail: node.role == .you ? String(localized: "local network and beyond") : nil)
                }
                if let rtt = RouteText.rtt(node.rttRange) {
                    tile(String(localized: "Response time"), rtt, detail: String(localized: "inside this network"))
                }
                if let routes = node.routeCount {
                    tile(String(localized: "Seen in"), String(localized: "\(routes) routes"), detail: nil)
                }
            }
            if node.ttls != nil {
                let answered = node.hops.filter { $0.kind != .silent }.count
                Text("Hops answered: \(answered) of \(node.hops.count)").font(.footnote).foregroundStyle(.secondary)
                ForEach(node.hops, id: \.ttl) { hop in
                    HStack {
                        Text("\(hop.ttl)").font(.footnote.weight(.semibold).monospacedDigit()).frame(width: 24, alignment: .leading)
                        Text(hop.kind == .silent ? String(localized: "No reply") : (hop.address ?? "")).font(.footnote).lineLimit(1)
                        Spacer()
                        if !hop.rtts.isEmpty {
                            Text(Format.rtt(hop.rtts.reduce(0, +) / Double(hop.rtts.count))).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roleText: String {
        switch node.role {
        case .you: String(localized: "Your network")
        case .transit: String(localized: "Transit network")
        case .destination: String(localized: "Destination")
        case .youAndDestination: String(localized: "Your network and the destination")
        }
    }

    private func tile(_ title: String, _ value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}
