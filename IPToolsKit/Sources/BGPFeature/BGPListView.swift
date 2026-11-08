// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

/// Accessible alternative to the graph: the same data as sections of rows.
struct BGPListView: View {
    let model: BGPMapModel

    @State private var expandedLayers: Set<Int> = []
    @State private var showAllPaths = false

    private static let pathLimit = 50

    var body: some View {
        if let result = model.result, let stats = model.stats {
            List {
                originSection(result: result, stats: stats)
                ForEach(layers(result.graph), id: \.self) { layer in
                    layerSection(layer, result: result, stats: stats)
                }
                pathsSection(stats: stats)
            }
            .groupedListStyle()
        }
    }

    private func layers(_ graph: ASGraph) -> [Int] {
        guard graph.layerCount > 1 else { return [] }
        return Array(1..<graph.layerCount)
    }

    private func originSection(result: BGPResult, stats: BGPStats) -> some View {
        Section("Origin") {
            ForEach(result.originASNs, id: \.self) { asn in row(asn, result: result, stats: stats) }
        }
    }

    @ViewBuilder
    private func layerSection(_ layer: Int, result: BGPResult, stats: BGPStats) -> some View {
        let members = stats.layerMembers[layer] ?? []
        if !members.isEmpty {
            let expanded = expandedLayers.contains(layer)
            let shownNodes = result.graph.nodes.compactMap { node -> UInt32? in
                node.layer == layer ? node.id.asnValue : nil
            }
            let shown = expanded ? members : members.filter { shownNodes.contains($0) }
            Section {
                ForEach(shown, id: \.self) { asn in row(asn, result: result, stats: stats) }
                if !expanded, shown.count < members.count {
                    Button("Show all \(members.count)") { expandedLayers.insert(layer) }
                }
            } header: {
                Text("\(BGPText.hops(layer)) · \(members.count) ASes")
            }
        }
    }

    private func row(_ asn: UInt32, result: BGPResult, stats: BGPStats) -> some View {
        let count = stats.pathCount[asn] ?? 0
        let role = stats.role(of: asn)
        let summary = BGPStats.Summary(id: .asn(asn), asn: asn, role: role, paths: count, fraction: stats.fraction(count),
                                       hops: stats.layer[asn] ?? 0, collapsed: [])
        let onPath = result.graph.highlightPathNodeIDs.contains(.asn(asn))
        let prefix = asn == model.myASN ? String(localized: "Your network, ")
            : (onPath ? String(localized: "On your path, ") : "")
        return Button { model.requestDetails(for: .asn(asn)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "AS\(asn)").font(.body.weight(.semibold)).monospacedDigit()
                    if onPath {
                        Text("Your path").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue))
                    }
                    Text(BGPText.shortName(model.holder(of: asn)) ?? "")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(BGPText.roleName(role)).font(.caption).foregroundStyle(.secondary)
                    Text("\(count)").font(.subheadline).monospacedDigit()
                }
                ProgressView(value: Double(count), total: Double(max(stats.total, 1)))
                    .progressViewStyle(.linear)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prefix + BGPText.accessibilityLabel(for: summary, names: result.names))
        .accessibilityAddTraits(.isButton)
    }

    private func pathsSection(stats: BGPStats) -> some View {
        let shown = showAllPaths ? stats.groups : Array(stats.groups.prefix(Self.pathLimit))
        return Section {
            ForEach(shown, id: \.self) { group in
                HStack {
                    Text(group.text).font(.system(.footnote, design: .monospaced))
                    Spacer(minLength: 8)
                    Text("×\(group.count)").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Path \(group.text), seen \(group.count) times"))
            }
            if !showAllPaths, stats.groups.count > Self.pathLimit {
                Button("Show all \(stats.groups.count)") { showAllPaths = true }
            }
        } header: {
            Text("AS paths · \(stats.groups.count) unique")
        }
    }
}

extension View {
    /// Inset grouped list on iOS, plain inset elsewhere.
    @ViewBuilder func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }
}
