// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation

/// Text helpers for the user's measured path: node details and the VoiceOver sentence (DESIGN 6.11.10).
enum RouteText {
    static func spokenASN(_ asn: UInt32) -> String { "AS \(asn)" }

    static func hops(_ range: ClosedRange<Int>?) -> String? {
        guard let range else { return nil }
        return range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }

    /// How many of a You node's answered hops are private addresses, and whether that is all of them.
    enum LocalHops: Equatable { case none, all, mixed(Int) }

    static func localHops(_ node: ASChain.Node) -> LocalHops {
        guard node.role == .you || node.role == .youAndDestination else { return .none }
        let answered = node.hops.filter { $0.kind != .silent }
        let local = answered.filter { $0.kind == .privateAddress }.count
        if local == 0 { return .none }
        return local == answered.count ? .all : .mixed(local)
    }

    static func rtt(_ range: ClosedRange<TimeInterval>?) -> String? {
        guard let range else { return nil }
        let low = Int((range.lowerBound * 1000).rounded()), high = Int((range.upperBound * 1000).rounded())
        return low == high ? "\(low) ms" : "\(low)–\(high) ms"
    }

    static func role(_ role: ASChain.Node.Role) -> String {
        switch role {
        case .you: return String(localized: "Your network")
        case .transit: return String(localized: "Transit network")
        case .destination: return String(localized: "Destination")
        case .youAndDestination: return String(localized: "Your network and the destination")
        }
    }
}

extension YourRouteModel {
    /// Number of hops the trace covered.
    var hopCount: Int {
        let all = chain?.nodes.flatMap(\.hops).map(\.ttl) ?? []
        return max(all.max() ?? 0, chain?.lastTTL ?? 0)
    }

    var targetLabel: String { context?.label ?? "" }

    // MARK: Accessibility (DESIGN 6.11.10)

    public var accessibilitySentence: String {
        guard let chain else { return "" }
        func spoken(_ node: ASChain.Node) -> String {
            guard let asn = node.asn else { return String(localized: "your network") }
            return RouteText.spokenASN(asn) + (shortName(asn).map { " \($0)" } ?? "")
        }
        let nodes = chain.nodes
        if nodes.count == 1, nodes[0].role == .youAndDestination {
            return String(localized: "Your route to \(targetLabel): this address is on your own network, \(spoken(nodes[0])).")
        }
        let sourceText: String
        switch chain.source {
        case .bgp: sourceText = String(localized: "seen in BGP")
        case .traceroute: sourceText = String(localized: "measured by traceroute")
        }
        let head = String(localized: "Your route to \(targetLabel), \(sourceText): ")
        guard let first = nodes.first, let last = nodes.last, nodes.count > 1 else { return head }
        var middle = nodes.dropFirst().dropLast().map(spoken)
        var phrase = String(localized: "from your network") + (first.asn != nil ? ", " + spoken(first) : "")
        let unknownGap = chain.completion == .gap
        if !middle.isEmpty {
            phrase += ", " + String(localized: "through") + " " + middle.removeFirst()
            for node in middle { phrase += ", " + String(localized: "then") + " " + node }
        }
        if unknownGap { phrase += ", " + String(localized: "then unknown networks") }
        let direct = nodes.count == 2 && !unknownGap
        phrase += ", " + (direct ? String(localized: "directly to") : String(localized: "to")) + " " + spoken(last)
            + ", " + String(localized: "the destination") + "."
        var tail = ""
        switch (chain.source, chain.completion) {
        case (.bgp, _): break
        case (_, .inProgress):
            if case let .measuring(ttl) = phase, ttl > 0 { tail = " " + String(localized: "Measuring, hop \(ttl).") }
        case (_, .complete): tail = " " + String(localized: "\(hopCount) hops.")
        case (_, .stitched): tail = " " + String(localized: "Traceroute stopped at hop \(chain.lastTTL ?? 0). The rest is from BGP.")
        case (_, .gap): tail = " " + String(localized: "Traceroute stopped at hop \(chain.lastTTL ?? 0).")
        }
        return head + phrase + tail
    }
}
