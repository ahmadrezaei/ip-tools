// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation

/// What the header says about the user's own path.
enum YourPathStatus: Equatable, Sendable { case hidden, measuring, shown, partial }

/// The ASN sequence drawn on the graph as the blue overlay.
struct PathOverlay: Equatable, Sendable {
    var asns: [UInt32] = []
    /// The last hop (to the origin) is expected, not observed: drawn dashed.
    var hasGap = false
    static let none = PathOverlay()
}

extension YourRouteModel {
    private var drawablePath: ASChain? {
        guard let chain, chain.asnSequence.count >= 2 || chain.completion == .complete else { return nil }
        return chain
    }

    var pathStatus: YourPathStatus {
        switch phase {
        case .measuring:
            return .measuring
        case .done, .partial, .stopped:
            guard let chain = drawablePath else { return .hidden }
            return chain.completion == .gap || chain.completion == .inProgress ? .partial : .shown
        case .idle, .locating, .lookupsOff, .unavailable, .failed:
            return .hidden
        }
    }

    var pathOverlay: PathOverlay {
        switch phase {
        case .measuring, .done, .partial, .stopped:
            guard let chain = drawablePath else { return .none }
            return PathOverlay(asns: chain.asnSequence, hasGap: chain.nodes.last?.provenance == .expected)
        case .idle, .locating, .lookupsOff, .unavailable, .failed:
            return .none
        }
    }

    /// "Your path: AS24940 Hetzner → AS13335 Cloudflare → AS15169 Google (measured by traceroute)"; nil when there is none.
    var exportLine: String? {
        guard let chain = drawablePath, pathStatus == .shown || pathStatus == .partial else { return nil }
        var items = chain.asnSequence.map { asn in "AS\(asn)" + (shortName(asn).map { " \($0)" } ?? "") }
        let gap = chain.nodes.last?.provenance == .expected
        if gap, items.count >= 1 { items.insert(String(localized: "unknown networks"), at: items.count - 1) }
        let source: String
        switch (chain.source, chain.completion) {
        case (.bgp, _): source = String(localized: "seen in BGP from your network")
        case (_, .stitched): source = String(localized: "measured by traceroute, rest from BGP")
        case (_, .gap): source = String(localized: "partly measured by traceroute")
        default: source = String(localized: "measured by traceroute")
        }
        return String(localized: "Your path: ") + items.joined(separator: " → ") + " (\(source))"
    }
}
