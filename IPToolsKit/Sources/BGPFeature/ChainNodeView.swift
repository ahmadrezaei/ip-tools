// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SharedUI
import SwiftUI

/// One network on the route.
struct ChainNodeView: View {
    enum Layout { case row, column }

    let node: ASChain.Node
    let route: YourRouteModel
    var layout: Layout = .row
    var isSelected = false
    var isLastSeen = false
    var isMeasuring = false
    var showsChevron = true

    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 32

    private var chain: ASChain? { route.chain }
    private var isExpected: Bool { node.provenance == .expected }
    private var isStitched: Bool {
        if node.provenance == .bgp, case .traceroute? = chain?.source { true } else { false }
    }
    private var prefix: String { route.context?.prefix ?? "" }

    private var title: String {
        if let asn = node.asn { return route.shortName(asn) ?? "AS\(asn)" }
        return String(localized: "Your network")
    }

    var body: some View {
        Group {
            switch layout {
            case .row: rowBody
            case .column: columnBody
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: layout == .row ? 64 : 108, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cardBackground))
        .overlay(outline)
        .opacity(isExpected ? 0.45 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(route.accessibilityLabel(for: node))
        .accessibilityHint(Text("Double-tap for details."))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var rowBody: some View {
        HStack(alignment: .center, spacing: 12) {
            roleCircle
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                Text(roleText).font(.footnote).foregroundStyle(.secondary)
                detailLine
            }
            Spacer(minLength: 4)
            if isStitched { fromBGPTag }
            if showsChevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
    }

    private var columnBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                roleCircle
                Spacer(minLength: 0)
                if isStitched { fromBGPTag }
            }
            if let asn = node.asn { Text(verbatim: "AS\(asn)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary) }
            Text(title).font(.headline).lineLimit(2)
            Text(roleText).font(.footnote).foregroundStyle(.secondary)
            detailLine
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(title).font(.body.weight(.semibold)).lineLimit(1)
            if let asn = node.asn {
                Text(verbatim: "AS\(asn)")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var roleCircle: some View {
        let fill: Color = node.role == .destination ? .accentColor : (node.role == .transit ? Color.primary.opacity(0.12) : .green)
        let symbol: String = switch node.role {
        case .you, .youAndDestination: "person.fill"
        case .transit: "arrow.down"
        case .destination: "flag.fill"
        }
        return Image(systemName: symbol)
            .font(.system(size: circle * 0.45, weight: .semibold))
            .foregroundStyle(node.role == .transit ? Color.primary : Color.white)
            .frame(width: circle, height: circle)
            .background(Circle().fill(fill))
    }

    private var fromBGPTag: some View {
        Text("from BGP")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
    }

    @ViewBuilder private var outline: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if isSelected {
            shape.strokeBorder(Color.accentColor, lineWidth: 2)
        } else if isExpected {
            shape.strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
    }

    private var roleText: String {
        switch node.role {
        case .you:
            return String(localized: "Your network")
        case .transit:
            return isLastSeen ? String(localized: "Transit network · last network seen") : String(localized: "Transit network")
        case .destination:
            return String(localized: "Destination · announces \(prefix)")
        case .youAndDestination:
            return String(localized: "Your network · announces \(prefix)")
        }
    }

    @ViewBuilder private var detailLine: some View {
        if isExpected {
            Text(isMeasuring ? "Not reached yet" : "Not reached").font(.footnote).foregroundStyle(.secondary)
        } else if let ttls = node.ttls {
            HStack(spacing: 5) {
                if let range = node.rttRange {
                    Circle().fill(RTTColor.color(for: range.lowerBound)).frame(width: 7, height: 7).accessibilityHidden(true)
                }
                Text(measuredText(ttls)).font(.footnote).foregroundStyle(.secondary)
            }
        } else if node.role == .you, node.provenance == .measured {
            Text("No hops seen before the next network").font(.footnote).foregroundStyle(.secondary)
        } else if let routes = node.routeCount {
            Text(bgpText(routes)).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func measuredText(_ ttls: ClosedRange<Int>) -> String {
        let hops = RouteText.hops(ttls) ?? ""
        var text = String(localized: "Hops \(hops)")
        if node.role == .you { text += " " + String(localized: "(local)") }
        if let rtt = RouteText.rtt(node.rttRange) { text += " · " + rtt }
        if node.role == .destination, chain?.reachedTarget == true { text += " · " + String(localized: "reached") }
        return text
    }

    private func bgpText(_ routes: Int) -> String {
        var text = String(localized: "Seen in \(routes) routes")
        if node.role == .you, case let .bgp(collectors)? = chain?.source, !collectors.isEmpty {
            text += " · " + collectors.prefix(3).joined(separator: ", ")
        }
        return text
    }
}
