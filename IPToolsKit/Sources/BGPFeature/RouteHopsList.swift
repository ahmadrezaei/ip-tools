// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SharedUI
import SwiftUI

/// "Show 11 hops": compact hop rows grouped under their network.
struct RouteHopsList: View {
    let route: YourRouteModel
    var startsExpanded = false

    @State private var expanded = false

    private var groups: [(node: ASChain.Node, hops: [ChainHop])] {
        (route.chain?.nodes ?? []).compactMap { $0.hops.isEmpty ? nil : ($0, $0.hops) }
    }
    private var count: Int { groups.reduce(0) { $0 + $1.hops.count } }

    var body: some View {
        if count > 0 {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.node.id) { group in
                        header(group.node)
                        ForEach(group.hops, id: \.ttl) { hop in
                            row(hop)
                            Divider()
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Show \(count) hops").font(.subheadline.weight(.medium))
            }
            .onAppear { expanded = startsExpanded }
        }
    }

    private func header(_ node: ASChain.Node) -> some View {
        let name = node.asn.flatMap { route.shortName($0) }
        let prefix = node.role == .you ? String(localized: "You") : (name ?? String(localized: "Network"))
        return HStack(spacing: 6) {
            Text(prefix).font(.footnote.weight(.semibold))
            if let asn = node.asn { Text(verbatim: "AS\(asn)").font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Color.accentColor) }
            if let local = localLabel(node) { Text(local).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.top, 10).padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }

    private func localLabel(_ node: ASChain.Node) -> String? {
        switch RouteText.localHops(node) {
        case .none: nil
        case .all: String(localized: "local network")
        case let .mixed(count): String(localized: "\(count) local hops")
        }
    }

    private func row(_ hop: ChainHop) -> some View {
        HStack(spacing: 10) {
            Text("\(hop.ttl)").font(.caption.weight(.semibold).monospacedDigit())
                .frame(width: 24, height: 24).background(Circle().fill(Color.fieldFill))
            VStack(alignment: .leading, spacing: 1) {
                switch hop.kind {
                case .silent: Text("No reply · * *").foregroundStyle(.secondary)
                default: Text(hop.hostname.map { "\($0) · \(hop.address ?? "")" } ?? hop.address ?? "").lineLimit(1).truncationMode(.middle)
                }
                if hop.kind == .privateAddress { Text("Private").font(.caption2).foregroundStyle(.secondary) }
            }
            .font(.footnote)
            Spacer(minLength: 6)
            if hop.rtts.isEmpty {
                Text("—").foregroundStyle(.secondary)
            } else {
                let average = hop.rtts.reduce(0, +) / Double(hop.rtts.count)
                Text(Format.rtt(average)).font(.footnote.monospacedDigit()).foregroundStyle(RTTColor.color(for: average))
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
