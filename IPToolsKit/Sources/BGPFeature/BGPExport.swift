// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import CoreTransferable
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum BGPExport {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter
    }()

    private static let pathLimit = 100

    /// Plain-text summary (DESIGN §6.10).
    static func text(result: BGPResult?, yourPath: String? = nil) -> String {
        guard let result else { return "" }
        let stats = BGPStats(graph: result.graph)
        let origins = result.originASNs.map { asn -> String in
            ["AS\(asn)", BGPText.fullName(result.holder(of: asn))].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: ", ")
        var lines = ["BGP paths for \(result.prefix)" + (origins.isEmpty ? "" : " (origin \(origins))")]
        var source = "Source: RIPE RIS via RIPEstat looking-glass, \(result.collectors.count) collectors, \(result.graph.totalPaths) paths"
        if let time = result.latestTime { source += ", " + timeFormatter.string(from: time) }
        lines.append(source)
        if let yourPath { lines.append(yourPath) }

        let seen = (stats.layerMembers[1] ?? []).filter { stats.pathCount[$0] != nil }
        let upstreams = seen.prefix(10).map { asn -> String in
            let name = BGPText.shortName(result.holder(of: asn)).map { " \($0)" } ?? ""
            return "AS\(asn)\(name) (\(stats.pathCount[asn] ?? 0))"
        }
        if !upstreams.isEmpty { lines.append("Upstreams (1 hop): " + upstreams.joined(separator: ", ")) }

        lines.append("Unique AS paths:")
        for group in stats.groups.prefix(pathLimit) { lines.append("  \(group.text)   ×\(group.count)") }
        if stats.groups.count > pathLimit { lines.append("  … and \(stats.groups.count - pathLimit) more") }
        return lines.joined(separator: "\n")
    }
}

/// Static rendering of the graph used for "Share as image".
struct GraphSnapshotView: View {
    let result: BGPResult
    let layout: GraphLayout

    var body: some View {
        let nodes = result.graph.nodes
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: result.prefix).font(.system(size: 22, weight: .bold, design: .monospaced))
            Text("\(result.graph.totalPaths) paths · \(result.collectors.count) collectors · RIPE RIS via RIPEstat")
                .font(.footnote).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                GraphEdgesLayer(layout: layout, highlight: nil)
                ForEach(nodes) { node in
                    if let frame = layout.frames[node.id] {
                        NodeView(node: node, name: node.id.asnValue.flatMap { BGPText.shortName(result.holder(of: $0)) },
                                 isOnPath: result.graph.highlightPathNodeIDs.contains(node.id))
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .overlay { RowCaptionsLayer(layout: layout) }
        }
        .padding(16)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// Lazily rendered PNG of the graph for `ShareLink`.
struct GraphImageExport: Transferable, Sendable {
    let result: BGPResult
    let layout: GraphLayout

    enum RenderError: Error { case failed }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await MainActor.run { try item.renderPNG() }
        }
    }

    @MainActor func renderPNG() throws -> Data {
        let renderer = ImageRenderer(content: GraphSnapshotView(result: result, layout: layout))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw RenderError.failed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.failed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.failed }
        return data as Data
    }
}
