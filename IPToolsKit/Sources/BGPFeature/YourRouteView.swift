// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SharedUI
import SwiftUI

/// Failure of the route measurement, shown through `ErrorStateView`.
struct RouteFailure: DisplayableError {
    let message: String
    var title: String { String(localized: "Couldn't measure your route") }
    var systemImage: String { "exclamationmark.triangle" }
    var action: ErrorAction? { .retry }
}

/// The default BGP view: the chain of networks between you and the destination (DESIGN 6.11).
struct YourRouteView: View {
    let model: BGPMapModel
    var showsHops: Bool? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPrivacyNote = false
    @State private var availableWidth: CGFloat = 0

    private var route: YourRouteModel { model.route }
    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) { content }
                .frame(maxWidth: isRegular ? 900 : 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.bottom, 16)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { availableWidth = chainWidth(proxy.size.width) }
                            .onChange(of: proxy.size.width) { _, width in availableWidth = chainWidth(width) }
                    }
                }
        }
        .onAppear {
            showPrivacyNote = !route.privacyNoteSeen
        }
    }

    private func chainWidth(_ width: CGFloat) -> CGFloat { min(width - 32, isRegular ? 900 : 640) }

    @ViewBuilder private var content: some View {
        switch route.phase {
        case .idle:
            ProgressView().padding(.top, 40)
        case .lookupsOff:
            ContentUnavailableView {
                Label("Network Lookups Are Off", systemImage: "network.slash")
            } description: {
                Text("Your route needs to look up which network each router belongs to (via RIPEstat).")
            } actions: {
                Button("Turn On Lookups") { route.turnOnLookups() }.buttonStyle(.borderedProminent)
            }
        case .unavailable:
            ContentUnavailableView("Route measurement isn't available here.", systemImage: "network.slash")
        case let .failed(message):
            ErrorStateView(RouteFailure(message: message)) { route.measureAgain() }
        case .locating:
            RouteStatusCard(route: route)
            skeleton
        case .measuring, .done, .partial, .stopped:
            RouteStatusCard(route: route)
            chainSection
            if !route.isMeasuring { footer }
        }
    }

    // MARK: Chain

    @ViewBuilder private var chainSection: some View {
        if let chain = route.chain {
            Group {
                if useHorizontal(chain) {
                    HorizontalChainView(route: route)
                } else {
                    verticalChain(chain)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(route.accessibilitySentence)
        } else {
            Text("No networks were measured yet.").foregroundStyle(.secondary).padding(.vertical, 24)
        }
    }

    private func useHorizontal(_ chain: ASChain) -> Bool {
        guard isRegular, typeSize < .accessibility1 else { return false }
        return HorizontalChainView.fits(nodes: chain.nodes.count, width: availableWidth)
    }

    private func verticalChain(_ chain: ASChain) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(chain.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    let style = RouteLayout.rail(into: node, chain: chain)
                    ChainRail(style: style, label: RouteLayout.railLabel(style: style, chain: chain, route: route))
                        .transition(.opacity)
                }
                if node.provenance == .expected, route.isMeasuring, case let .measuring(ttl) = route.phase {
                    pendingRow(ttl: ttl + 1)
                    ChainRail(style: .dashed)
                }
                Button { toggle(node) } label: {
                    ChainNodeView(node: node, route: route, isSelected: route.selection == node.id,
                                  isLastSeen: RouteLayout.isLastSeen(node, chain: chain), isMeasuring: route.isMeasuring)
                }
                .buttonStyle(.plain)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: chain.nodes.map(\.id))
    }

    private func pendingRow(ttl: Int) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).frame(width: 32)
            Text("Hop \(ttl)…").font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var skeleton: some View {
        let origin = route.context?.origins.first
        let you = ASChain.Node(asn: nil, role: .you, provenance: .measured)
        let destination = ASChain.Node(asn: origin, role: .destination, provenance: .expected, gapBefore: true)
        return VStack(spacing: 0) {
            ChainNodeView(node: you, route: route, showsChevron: false).redacted(reason: .placeholder)
            ChainRail(style: .dashed)
            ChainNodeView(node: destination, route: route, isMeasuring: true, showsChevron: false)
        }
    }

    private func toggle(_ node: ASChain.Node) {
        route.selection = route.selection == node.id ? nil : node.id
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let caption = route.collectorCaption {
                Text(caption).font(.footnote).foregroundStyle(.secondary)
            }
            Text(sourceLine).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button { route.measureAgain() } label: {
                    Label(route.isBGPSourced ? "Measure with traceroute" : "Measure again", systemImage: route.isBGPSourced ? "scope" : "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            if !route.isBGPSourced { RouteHopsList(route: route, startsExpanded: showsHops ?? false) }
            if showPrivacyNote, !route.isBGPSourced {
                Text("Your public IP and the routers' addresses were looked up at RIPEstat (RIPE NCC).")
                    .font(.caption).foregroundStyle(.secondary)
                    .onAppear { route.markPrivacyNoteSeen() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var sourceLine: String {
        switch route.chain?.source {
        case .bgp:
            return String(localized: "Path \(route.chain?.asnSequence.map { "AS\($0)" }.joined(separator: " → ") ?? "") from the live RIS data for \(route.context?.prefix ?? "").")
        case let .traceroute(handedOver, _):
            return handedOver
                ? String(localized: "From your traceroute (Map in BGP) · networks looked up at RIPEstat")
                : String(localized: "Measured from this device · networks looked up at RIPEstat")
        case nil:
            return ""
        }
    }
}

/// Shared rules for how links and nodes of a chain are drawn.
enum RouteLayout {
    static func rail(into node: ASChain.Node, chain: ASChain) -> RailStyle {
        if node.gapBefore, chain.completion == .gap { return .gap }
        if node.provenance == .measured { return .solid }
        return .dashed
    }

    @MainActor static func railLabel(style: RailStyle, chain: ASChain, route: YourRouteModel) -> String? {
        switch style {
        case .gap:
            let first = (chain.lastTTL ?? 0) + 1
            let last = route.hops.map(\.ttl).max() ?? first
            if last > first { return String(localized: "Unknown · hops \(first)–\(last) didn't answer") }
            if last == first { return String(localized: "Unknown · hop \(first) didn't answer") }
            return String(localized: "Unknown networks")
        case .dashed:
            if case .bgp = chain.source { return String(localized: "connects directly") }
            return nil
        case .solid:
            return nil
        }
    }

    /// The last measured network before a gap.
    static func isLastSeen(_ node: ASChain.Node, chain: ASChain) -> Bool {
        guard chain.completion == .gap || chain.completion == .stitched else { return false }
        guard node.provenance == .measured, node.role == .transit else { return false }
        return chain.nodes.last { $0.provenance == .measured } == node
    }
}
