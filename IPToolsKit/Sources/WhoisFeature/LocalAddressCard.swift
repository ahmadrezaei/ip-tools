// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import SharedUI
import SwiftUI

/// Wording and symbols for the answer given without a request (DESIGN §14.3.4).
extension LocalVerdict {
    private var range: SpecialPurposeRange? {
        if case let .address(range) = reason { range } else { nil }
    }

    var title: String {
        switch reason {
        case let .asn(reserved):
            switch reserved.name {
            case "Private use": String(localized: "Private AS number")
            case "Documentation": String(localized: "Documentation AS number")
            default: String(localized: "Reserved AS number")
            }
        case let .address(range):
            switch range.kind {
            case .privateUse, .uniqueLocal: String(localized: "Private address")
            case .sharedCGNAT: String(localized: "Shared address (CGNAT)")
            case .documentation: String(localized: "Documentation address")
            case .loopback: String(localized: "Loopback address")
            case .linkLocal: String(localized: "Link-local address")
            case .multicast: String(localized: "Multicast address")
            case .ipv4Mapped, .nat64, .sixToFour: String(localized: "Address with an IPv4 address inside")
            default: String(localized: "Reserved address")
            }
        }
    }

    var systemImage: String {
        guard let range else { return "nosign" }
        switch range.kind {
        case .privateUse, .uniqueLocal: return "lock"
        case .sharedCGNAT: return "building.2"
        case .documentation: return "book.closed"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .multicast: return "antenna.radiowaves.left.and.right"
        default: return "nosign"
        }
    }

    /// "192.168.0.0/16", "AS64512 – AS65534"
    var rangeText: String {
        switch reason {
        case let .address(range): "\(range.network)/\(range.length)"
        case let .asn(reserved):
            reserved.range.lowerBound == reserved.range.upperBound
                ? "AS\(reserved.range.lowerBound)" : "AS\(reserved.range.lowerBound) – AS\(reserved.range.upperBound)"
        }
    }

    var typeText: String {
        switch reason {
        case let .address(range): range.name
        case let .asn(reserved): reserved.name
        }
    }

    var standard: String {
        switch reason {
        case let .address(range): range.rfc
        case let .asn(reserved): reserved.rfc
        }
    }

    /// One plain sentence: what it is and why no registry has it.
    var sentence: String {
        let input = self.input
        switch reason {
        case let .asn(reserved):
            return reserved.name == "Private use"
                ? String(localized: "\(input) is a private-use AS number (\(reserved.rfc)). Networks use it internally; it has no registry record.")
                : String(localized: "\(input) is a \(reserved.name.lowercased()) AS number (\(reserved.rfc)). It has no registry record.")
        case let .address(range):
            let cidr = "\(range.network)/\(range.length)"
            switch range.kind {
            case .privateUse, .uniqueLocal:
                return String(localized: "\(input) is in \(cidr), a private range (\(range.rfc)). It's only used inside local networks, so no registry has a whois record for it.")
            case .sharedCGNAT:
                return String(localized: "\(input) is in \(cidr), shared address space (\(range.rfc)). Carriers use it inside their networks for CGNAT; it never appears on the public Internet.")
            case .documentation:
                return String(localized: "\(input) is in \(cidr), reserved for documentation and examples (\(range.rfc)). It is never used on real networks.")
            default:
                return String(localized: "\(input) is in \(cidr), \(range.name.lowercased()) (\(range.rfc)). It isn't a public address, so no registry has a whois record for it.")
            }
        }
    }
}

/// Private, reserved, CGNAT, documentation and special-ASN answers. No request was made for these.
struct LocalAddressCard: View {
    let verdict: LocalVerdict
    var onPing: () -> Void = {}
    var onTrace: () -> Void = {}
    var onLookUpEmbedded: (IPAddress) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 12) {
            card
            if let embedded = verdict.embeddedIPv4 {
                Button { onLookUpEmbedded(embedded) } label: {
                    Text("Look up \(embedded.description) instead").frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }
            if verdict.canProbe {
                WhoisActions(showsMap: false, onPing: onPing, onTrace: onTrace)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: verdict.systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verdict.title).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(verdict.sentence).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            WhoisRow("Range", text: verdict.rangeText)
            WhoisRow("Type", text: verdict.typeText)
            WhoisRow("Standard", text: verdict.standard)
            WhoisRow("Routed on the Internet", text: String(localized: "No"))
        }
        .padding(.bottom, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }
}

/// "Your public IP is 193.0.6.139 ›" under a local answer; returns to My IP.
struct MyIPHintRow: View {
    let address: IPAddress
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("Your public IP is \(address.description)")
                Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
            }
            .font(.footnote)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .accessibilityLabel(String(localized: "Your public IP is \(IPSpeech.plain(address))"))
        .accessibilityHint(String(localized: "Shows your public IP"))
    }
}
