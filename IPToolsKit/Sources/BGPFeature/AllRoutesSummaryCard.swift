// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

/// Plain sentences about the worldwide routes (DESIGN 6.12 item 2).
struct AllRoutesSummaryCard: View {
    let result: BGPResult
    let summary: RoutesSummary
    var myNetwork: MyNetwork?
    @Binding var mode: BGPMapModel.DisplayMode
    var showUpdated = false
    var onSeeYourRoute: () -> Void = {}

    private var originName: String? { BGPText.originName(result) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("**\(summary.totalRoutes) routes** from \(summary.collectorCount) RIPE collectors")
                    directLine
                    yourNetworkLine
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { mode = mode == .graph ? .list : .graph } label: {
                    Image(systemName: mode == .graph ? "list.bullet" : "point.3.connected.trianglepath.dotted")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .graph ? Text("Show as list") : Text("Show as graph"))
            }
            chips
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var directLine: some View {
        let percent = Int((summary.directFraction * 100).rounded())
        let target = originName ?? String(localized: "the destination")
        let handoffs = summary.handoffs.map { asn -> String in
            "**AS\(asn)" + (BGPText.shortName(result.holder(of: asn)).map { " \($0)" } ?? "") + "**"
        }
        if let first = handoffs.first {
            let others = handoffs.count > 1
                ? "\(first) " + String(localized: "or") + " \(handoffs[1])"
                : first
            Text("**\(percent)%** connect to \(target) directly. Most others pass through \(others).")
        } else {
            Text("**\(percent)%** connect to \(target) directly.")
        }
    }

    @ViewBuilder private var yourNetworkLine: some View {
        if let asn = myNetwork?.asn, let count = summary.myASNRouteCount {
            let name = BGPText.shortName(result.holder(of: asn)) ?? myNetwork?.name
            let label = "AS\(asn)" + (name.map { " \($0)" } ?? "")
            if count > 0 {
                Text("**Your network** (\(label)) is in \(count) routes, highlighted below")
            } else {
                HStack(spacing: 4) {
                    Text("Your network (\(label)) isn't in these routes.")
                    Button(action: onSeeYourRoute) { Text("**See Your route ›**") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if result.originASNs.count > 1 {
                    chip(String(localized: "\(result.originASNs.count) origin ASes"), systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                if let visibility = result.visibility {
                    chip(String(localized: "Seen by \(visibility.seeing)/\(visibility.total) peers"))
                }
                if summary.totalRoutes < 3 {
                    chip(String(localized: "Seen by few collectors"), tint: .orange)
                }
                if showUpdated, let time = result.latestTime {
                    chip(String(localized: "Updated \(PrefixHeaderCard.timeFormatter.string(from: time)) UTC"))
                }
            }
        }
    }

    private func chip(_ text: String, systemImage: String? = nil, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint == .secondary ? Color.primary : tint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(tint == .secondary ? 0.12 : 0.18)))
    }
}
