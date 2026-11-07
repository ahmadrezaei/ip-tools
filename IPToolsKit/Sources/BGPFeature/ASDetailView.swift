// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SharedUI
import SwiftUI

/// Details of one AS (or a "+more" bucket). Sheet on iPhone, inspector on iPad.
struct ASDetailView: View {
    let model: BGPMapModel
    let id: NodeID

    @State private var showAllPaths = false
    @Environment(\.openURL) private var openURL

    private static let pathLimit = 50

    var body: some View {
        ScrollView {
            if let result = model.result, let stats = model.stats,
               let summary = stats.summary(for: id, graph: result.graph) {
                content(result: result, stats: stats, summary: summary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("No details", systemImage: "questionmark.circle")
            }
        }
    }

    @ViewBuilder
    private func content(result: BGPResult, stats: BGPStats, summary: BGPStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(result: result, summary: summary)
            badges(summary: summary)
            tiles(stats: stats, summary: summary)
            if summary.asn == nil { collapsedList(result: result, stats: stats, summary: summary) }
            paths(stats: stats, summary: summary)
            if let asn = summary.asn { actions(asn) }
        }
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
