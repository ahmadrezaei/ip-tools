// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

/// Shown after a finished trace: reached / didn't reach / stopped.
struct TraceSummaryCard: View {
    let completion: TraceCompletion
    let target: ResolvedTarget?
    let hops: [TraceHop]
    let maxHops: Int

    /// Resolved host name of the destination hop, else the target's host name, else what was typed.
    private var name: String {
        hops.last(where: \.isDestination)?.hostname ?? target?.hostname ?? target?.input ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch completion {
        case .reachedDestination: "checkmark.circle.fill"
        case .unreachable: "xmark.octagon.fill"
        case .maxHopsExceeded: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch completion {
        case .reachedDestination: .green
        case .unreachable: .red
        case .maxHopsExceeded: .orange
        }
    }

    private var title: String {
        switch completion {
        case let .reachedDestination(count):
            String(localized: "Reached \(name) in \(count) hops")
        case let .unreachable(hop, code):
            String(localized: "Stopped: \(UnreachableReason(code: code, family: target?.address.family ?? .v4).noun) unreachable at hop \(hop)")
        case .maxHopsExceeded:
            String(localized: "Didn't reach \(name) within \(maxHops) hops")
        }
    }

    /// "8.8.8.8 · AS15169 Google · 12.9 ms"
    private var detail: String? {
        guard case .reachedDestination = completion, let last = hops.last(where: { $0.isDestination }) ?? hops.last else { return nil }
        var parts: [String] = []
        if let address = last.addresses.first { parts.append(address.description) }
        if let asn = last.asn { parts.append("AS\(asn.asn)" + (asn.name.map { " \($0)" } ?? "")) }
        if let rtt = last.averageRTT { parts.append(Format.rtt(rtt)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
