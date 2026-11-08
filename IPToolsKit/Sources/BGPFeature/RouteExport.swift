// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import Foundation
import SharedUI

/// Text helpers for the chain: node lines, export (DESIGN 6.11.11) and the VoiceOver sentence (6.11.10).
enum RouteText {
    static func spokenASN(_ asn: UInt32) -> String { "AS \(asn)" }

    static func hops(_ range: ClosedRange<Int>?) -> String? {
        guard let range else { return nil }
        return range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }

    static func rtt(_ range: ClosedRange<TimeInterval>?) -> String? {
        guard let range else { return nil }
        let low = Int((range.lowerBound * 1000).rounded()), high = Int((range.upperBound * 1000).rounded())
        return low == high ? "\(low) ms" : "\(low)–\(high) ms"
    }

    static let utc: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter
    }()

    static func localTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}

extension YourRouteModel {
    var isBGPSourced: Bool { if case .bgp? = chain?.source { true } else { false } }

    /// Number of hops the trace covered.
    var hopCount: Int {
        let all = chain?.nodes.flatMap(\.hops).map(\.ttl) ?? []
        return max(all.max() ?? 0, chain?.lastTTL ?? 0)
    }

    var targetLabel: String { context?.label ?? "" }

    var hasMeasuredNetwork: Bool {
        chain?.nodes.contains { $0.provenance == .measured && $0.asn != nil && $0.role != .you } ?? false
    }

    private func label(_ asn: UInt32?) -> String {
        guard let asn else { return String(localized: "your network") }
        return shortName(asn) ?? "AS\(asn)"
    }

    // MARK: Status card

    var statusTitle: String {
        switch phase {
        case .idle, .unavailable, .lookupsOff: return ""
        case .locating: return String(localized: "Finding your network…")
        case let .measuring(ttl):
            return ttl > 0 ? String(localized: "Measuring your route… hop \(ttl)") : String(localized: "Measuring your route…")
        case let .partial(title), let .stopped(title), let .failed(title): return title
        case .done:
            guard let chain else { return "" }
            if chain.nodes.count == 1, chain.nodes[0].role == .youAndDestination {
                let origin = chain.nodes[0].asn
                let name = origin.map { "AS\($0)" + (shortName($0).map { " \($0)" } ?? "") } ?? ""
                return String(localized: "\(targetLabel) is on your own network (\(name))")
            }
            if isBGPSourced, chain.nodes.count == 2 {
                return String(localized: "Your network connects directly to \(label(chain.nodes.last?.asn))")
            }
            return String(localized: "\(chain.nodes.count) networks between you and \(targetLabel)")
        }
    }

    var statusSubtitle: String? {
        guard let chain else {
            if case .stopped = phase { return String(localized: "Nothing was measured yet") }
            return nil
        }
        switch phase {
        case .measuring: return String(localized: "Traceroute from this device · usually 5–15 s")
        case .done:
            switch chain.source {
            case .bgp:
                let mine = chain.nodes.first?.routeCount ?? 0
                return String(localized: "Seen in BGP from your network · \(mine) of \(context?.paths.count ?? 0) routes")
            case let .traceroute(handedOver, date):
                var text = String(localized: "Measured by traceroute · \(hopCount) hops · \(RouteText.localTime(date))")
                if handedOver { text += " · " + String(localized: "from your traceroute") }
                return text
            }
        case .partial:
            if chain.completion == .stitched {
                let from = label(chain.nodes.last { $0.provenance == .measured }?.asn)
                let count = chain.nodes.first { $0.provenance == .bgp }?.routeCount ?? 0
                return String(localized: "The rest is the most common BGP route from \(from) (\(count) of \(context?.paths.count ?? 0) routes).")
            }
            if !hasMeasuredNetwork { return String(localized: "Some networks block traceroute.") }
            let from = label(chain.nodes.last { $0.provenance == .measured && $0.asn != nil }?.asn)
            let to = label(chain.nodes.last?.asn)
            return String(localized: "The networks between \(from) and \(to) are unknown.")
        case .stopped: return String(localized: "The part measured so far is kept.")
        default: return nil
        }
    }

    /// "Your network announces this route to RIPE collectors RRC01 (London) and RRC03 (Amsterdam)."
    var collectorCaption: String? {
        guard case let .bgp(collectors) = chain?.source, !collectors.isEmpty else { return nil }
        let items = collectors.map { id -> String in
            guard let place = context?.collectorLocations[id], !place.isEmpty else { return id }
            let city = place.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? place
            return "\(id) (\(city))"
        }
        let list = items.count > 1
            ? items.dropLast().joined(separator: ", ") + " " + String(localized: "and") + " " + (items.last ?? "")
            : items[0]
        return String(localized: "Your network announces this route to RIPE collectors \(list).")
    }

    // MARK: Export (DESIGN 6.11.11)

    public var exportText: String {
        guard let chain, let context else { return "" }
        var head = "Your route to \(context.label) (\(context.prefix)"
        if let origin = context.origins.first {
            head += ", origin AS\(origin)" + (fullName(origin).map { " \($0)" } ?? "")
        }
        head += ")"
        var lines = [head]
        switch chain.source {
        case let .bgp(collectors):
            lines.append("Seen in BGP from your network" + (collectors.isEmpty ? "" : " (\(collectors.joined(separator: ", ")))"))
        case let .traceroute(_, date):
            let count = hopCount
            lines.append("Measured by traceroute from this device, \(RouteText.utc.string(from: date)), \(count) \(count == 1 ? "hop" : "hops")")
        }
        struct Row { var mark = "", asn = "", name = "", info = "", rtt = "", note = "", gap = false }
        var rows: [Row] = []
        for (index, node) in chain.nodes.enumerated() {
            if node.gapBefore, chain.completion == .gap {
                rows.append(Row(mark: " ? ", name: "unknown networks", gap: true))
            }
            if node.provenance == .expected { continue }
            var row = Row(mark: index == 0 ? "You" : " → ", asn: node.asn.map { "AS\($0)" } ?? "-", name: shortName(node.asn) ?? "")
            if node.provenance == .bgp, case .bgp = chain.source {
                row.info = "×\(node.routeCount ?? 0) routes"
            } else if let hops = RouteText.hops(node.ttls) {
                row.info = "hops \(hops)"
                row.rtt = RouteText.rtt(node.rttRange) ?? ""
            }
            if node.provenance == .bgp, case .traceroute = chain.source { row.note = "(from BGP)" }
            if (node.role == .destination || node.role == .youAndDestination), chain.reachedTarget {
                row.note = "(reached \(context.label))"
            }
            rows.append(row)
        }
        let widths = (
            asn: rows.filter { !$0.gap }.map(\.asn.count).max() ?? 0, name: rows.filter { !$0.gap }.map(\.name.count).max() ?? 0,
            info: rows.map(\.info.count).max() ?? 0, rtt: rows.map(\.rtt.count).max() ?? 0)
        for row in rows {
            if row.gap { lines.append("   ?   unknown networks"); continue }
            let columns = [RouteText.pad(row.mark, 3), RouteText.pad(row.asn, widths.asn), RouteText.pad(row.name, widths.name),
                           RouteText.pad(row.info, widths.info), RouteText.pad(row.rtt, widths.rtt), row.note]
            var text = "  " + columns.joined(separator: "  ")
            while text.hasSuffix(" ") { text.removeLast() }
            lines.append(text)
        }
        lines.append("— IP Tools for iOS")
        return lines.joined(separator: "\n")
    }

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
        case (_, .complete): tail = " " + String(localized: "\(hopCount) hops.")
        case (_, .stitched): tail = " " + String(localized: "Traceroute stopped at hop \(chain.lastTTL ?? 0). The rest is from BGP.")
        default: tail = " " + String(localized: "Traceroute stopped at hop \(chain.lastTTL ?? 0).")
        }
        return head + phrase + tail
    }

    /// Spoken description of one node (the node is a button).
    func accessibilityLabel(for node: ASChain.Node) -> String {
        var parts: [String]
        switch node.role {
        case .you: parts = [String(localized: "Your network")]
        case .transit: parts = [String(localized: "Transit network")]
        case .destination: parts = [String(localized: "Destination")]
        case .youAndDestination: parts = [String(localized: "Your network, destination")]
        }
        if let asn = node.asn {
            parts.append(RouteText.spokenASN(asn))
            if let name = shortName(asn) { parts.append(name) }
        }
        if node.provenance == .expected {
            parts.append(String(localized: "not reached"))
        } else if let ttls = node.ttls {
            parts.append(ttls.count == 1 ? String(localized: "hop \(ttls.lowerBound)")
                                         : String(localized: "hops \(ttls.lowerBound) to \(ttls.upperBound)"))
            if let range = node.rttRange {
                let low = Int((range.lowerBound * 1000).rounded()), high = Int((range.upperBound * 1000).rounded())
                parts.append(low == high ? String(localized: "\(low) milliseconds")
                                         : String(localized: "\(low) to \(high) milliseconds"))
            }
        } else if let routes = node.routeCount {
            parts.append(String(localized: "seen in \(routes) routes"))
        }
        return parts.joined(separator: ", ") + "."
    }
}
