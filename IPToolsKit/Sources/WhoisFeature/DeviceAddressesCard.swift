// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import SharedUI
import SwiftUI

/// The one-sentence reading of the device's addresses next to the public one (DESIGN §14.5.6).
enum DeviceInterpretation {
    /// First match wins: CGNAT, NAT, no NAT on IPv6, nothing.
    static func line(local: [LocalAddress], publicV4: IPAddress?, publicV6: IPAddress?) -> String? {
        let v4 = local.filter { $0.address.family == .v4 }
        if let shared = v4.first(where: { isSharedSpace($0.address) }) {
            if let publicV4 {
                return String(localized: "Your carrier uses CGNAT: \(shared.address.description) is shared space, and many customers share \(publicV4.description).")
            }
            return String(localized: "Your carrier uses CGNAT: \(shared.address.description) is shared space.")
        }
        if let privateAddress = v4.first(where: { isPrivate($0.address) }), let publicV4 {
            return String(localized: "Your router translates \(privateAddress.address.description) to \(publicV4.description) (NAT).")
        }
        if let publicV6, local.contains(where: { $0.address == publicV6 }) {
            return String(localized: "Your IPv6 address is reachable as is (no NAT).")
        }
        return nil
    }

    /// CGNAT or a private address next to a public one (interpretation rules 1 and 2).
    static func isBehindNAT(local: [LocalAddress], publicV4: IPAddress?) -> Bool {
        let v4 = local.filter { $0.address.family == .v4 }
        return v4.contains { isSharedSpace($0.address) } || (publicV4 != nil && v4.contains { isPrivate($0.address) })
    }

    /// 100.64.0.0/10
    static func isSharedSpace(_ address: IPAddress) -> Bool {
        address.family == .v4 && address.bytes[0] == 100 && address.bytes[1] & 0xC0 == 0x40
    }

    /// 10/8, 172.16/12, 192.168/16
    static func isPrivate(_ address: IPAddress) -> Bool {
        guard address.family == .v4 else { return false }
        let b = address.bytes
        return b[0] == 10 || (b[0] == 172 && b[1] & 0xF0 == 16) || (b[0] == 192 && b[1] == 168)
    }
}

extension LocalAddress.Interface {
    func title(_ name: String) -> String {
        switch self {
        case .wifi: String(localized: "Wi-Fi")
        case .cellular: String(localized: "Cellular")
        case .wired: String(localized: "Wired")
        case .vpn: String(localized: "VPN (\(name))")
        case .other: name
        }
    }
}

/// "This device": the local addresses, read with getifaddrs and never sent anywhere.
struct DeviceAddressesCard: View {
    let addresses: [LocalAddress]
    let publicV4: IPAddress?
    let publicV6: IPAddress?
    /// iPad: one disclosure row that expands in place.
    var collapsible = false
    @State private var expanded = false

    var body: some View {
        if collapsible {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    HStack {
                        Text("This device").font(.headline)
                        Text(summaryLine).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                            .font(.footnote).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(expanded ? String(localized: "Collapses") : String(localized: "Expands"))
                if expanded { content }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WhoisSectionCaption("This device")
                VStack(alignment: .leading, spacing: 0) { content }
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)
            }
        }
    }

    private var summaryLine: String {
        guard let first = addresses.first else { return String(localized: "No addresses") }
        let nat = DeviceInterpretation.isBehindNAT(local: addresses, publicV4: publicV4)
        return "\(first.interface.title(first.name)) \(first.address.description)" + (nat ? " · " + String(localized: "behind NAT") : "")
    }

    @ViewBuilder private var content: some View {
        if addresses.isEmpty {
            Text("No network addresses on this device.").font(.subheadline).foregroundStyle(.secondary).padding(14)
        } else {
            ForEach(addresses) { local in
                WhoisRow(LocalizedStringKey(local.interface.title(local.name)),
                         spoken: "\(local.interface.title(local.name)), \(IPSpeech.plain(local.address))") {
                    Text(local.address.description).font(.body.monospaced()).textSelection(.enabled)
                        .copyContextMenu(local.address.description)
                }
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            if let line = DeviceInterpretation.line(local: addresses, publicV4: publicV4, publicV6: publicV6) {
                Text(line).font(.subheadline)
            }
            Text("Read from this device. Never sent anywhere.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

#Preview("This device") {
    ScrollView {
        DeviceAddressesCard(addresses: WhoisPreviewData.localAddresses, publicV4: WhoisPreviewData.myV4,
                            publicV6: WhoisPreviewData.myV6)
        DeviceAddressesCard(addresses: WhoisPreviewData.localAddresses, publicV4: WhoisPreviewData.myV4,
                            publicV6: WhoisPreviewData.myV6, collapsible: true)
    }
    .background(Color.screenBackground)
}
