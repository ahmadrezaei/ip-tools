// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// Floating summary of the selected node (iPhone). "Details" opens `ASDetailView` in a sheet.
struct SelectionCard: View {
    let summary: BGPStats.Summary
    let holder: String?
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                title
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onDetails) {
                Label("Details", systemImage: "chevron.right").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var title: some View {
        if let asn = summary.asn {
            if let name = BGPText.fullName(holder) {
                Text(verbatim: "AS\(asn) · \(name)").font(.subheadline.weight(.semibold)).lineLimit(1)
            } else {
                Text(verbatim: "AS\(asn)").font(.subheadline.weight(.semibold))
            }
        } else {
            Text("+\(summary.collapsed.count) more networks").font(.subheadline.weight(.semibold))
        }
    }

    private var subtitle: String {
        let paths = String(localized: "\(summary.paths) paths (\(BGPText.percent(summary.fraction)))")
        if summary.asn == nil { return "\(paths) · \(BGPText.hops(summary.hops))" }
        return "\(BGPText.roleName(summary.role)) · \(paths) · \(BGPText.hops(summary.hops))"
    }
}
