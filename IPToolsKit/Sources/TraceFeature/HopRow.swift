// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

/// One TTL: number circle, host, ASN badge + IP, average RTT with the individual probes below.
struct HopRow: View {
    let hop: TraceHop
    var isPending = false
    var onPing: (IPAddress) -> Void = { _ in }
    var onMap: (IPAddress) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            number
            VStack(alignment: .leading, spacing: 3) {
                title
                subtitle
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ScaledMetric(relativeTo: .footnote) private var circleSize: CGFloat = 28

    private var number: some View {
        Text("\(hop.ttl)")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(hop.isDestination ? Color.white : Color.primary)
            .frame(width: circleSize, height: circleSize)
            .background(Circle().fill(hop.isDestination ? Color.green : Color.fieldFill))
    }

    @ViewBuilder private var title: some View {
        if let address = hop.addresses.first {
            Text(hop.hostname ?? address.description)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("No reply").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var subtitle: some View {
        if let address = hop.addresses.first {
            HStack(spacing: 6) {
                if let asn = hop.asn {
                    Button { onMap(address) } label: {
                        Text("AS\(asn.asn)" + (asn.name.map { " \($0)" } ?? ""))
                            .lineLimit(1)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Maps this network in BGP")
                } else if let scope = address.scopeLabel {
                    badge(scope)
                }
                if hop.hostname != nil {
                    Text(address.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if hop.otherAddressCount > 0 {
                    Text("+\(hop.otherAddressCount) other").font(.caption).foregroundStyle(.secondary)
                }
                if let reason = hop.unreachableReason {
                    Text(reason.traceLabel).font(.caption.weight(.medium)).foregroundStyle(.red)
                }
            }
        } else {
            Text(Array(repeating: "*", count: max(hop.probes.count, 1)).joined(separator: " "))
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.fieldFill, in: Capsule())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var trailing: some View {
        if let average = hop.averageRTT {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.rtt(average))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(RTTColor.color(for: average))
                Text(probeText).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        } else if isPending {
            ProgressView().controlSize(.small)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    /// "9.4 · 8.9 · 10.2", `*` for a lost probe.
    var probeText: String {
        hop.probes.map { $0.rtt.map(Format.ms) ?? "*" }.joined(separator: " · ")
    }

    @ViewBuilder private var menu: some View {
        if let address = hop.addresses.first {
            Button { onPing(address) } label: { Label("Ping this hop", systemImage: Tool.ping.systemImage) }
            if address.isPubliclyRoutable {
                Button { onMap(address) } label: { Label("Map in BGP", systemImage: Tool.bgp.systemImage) }
            }
            Button { Clipboard.copy(address.description) } label: { Label("Copy IP", systemImage: "doc.on.doc") }
            if let hostname = hop.hostname {
                Button { Clipboard.copy(hostname) } label: { Label("Copy Hostname", systemImage: "doc.on.doc") }
            }
            if hop.addresses.count > 1 {
                Divider()
                ForEach(hop.addresses.dropFirst(), id: \.self) { other in
                    Button { Clipboard.copy(other.description) } label: { Label("Copy \(other.description)", systemImage: "doc.on.doc") }
                }
            }
        }
        Button { Clipboard.copy(TraceExport.line(for: hop, probes: hop.probes.count)) } label: {
            Label("Copy Row", systemImage: "doc.on.doc")
        }
    }

    private var accessibilityText: String {
        guard let address = hop.addresses.first else {
            return String(localized: "Hop \(hop.ttl), no reply")
        }
        var text = String(localized: "Hop \(hop.ttl), \(hop.hostname ?? address.description)")
        if let asn = hop.asn { text += ", AS\(asn.asn) \(asn.name ?? "")" }
        if let average = hop.averageRTT { text += ", " + Format.rtt(average) }
        return text
    }
}

/// "Hop 7…" with a spinner, shown for the TTL being probed before any answer arrives.
struct HopPlaceholderRow: View {
    let ttl: Int
    @ScaledMetric(relativeTo: .footnote) private var circleSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            Text("\(ttl)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .frame(width: circleSize, height: circleSize)
                .background(Circle().fill(Color.fieldFill))
            Text("Hop \(ttl)…").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            ProgressView().controlSize(.small)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
