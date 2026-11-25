// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct SpecialPurposeRange: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case thisNetwork, privateUse, sharedCGNAT, loopback, linkLocal, protocolAssignments, documentation,
             relayAnycast, benchmarking, multicast, reserved, broadcast,
             unspecified, ipv4Mapped, nat64, discard, teredo, sixToFour, uniqueLocal
    }

    public let network: IPAddress
    public let length: Int
    public let kind: Kind
    public let name: String            // "Private use", "Shared address space (CGNAT)"
    public let rfc: String             // "RFC 1918"

    public init(network: IPAddress, length: Int, kind: Kind, name: String, rfc: String) {
        self.network = network
        self.length = length
        self.kind = kind
        self.name = name
        self.rfc = rfc
    }

    /// "192.168.0.0/16"
    public var cidr: String { "\(network)/\(length)" }

    /// Ping/trace sensible: private, CGNAT, link-local, loopback, ULA.
    public var allowsProbing: Bool {
        switch kind {
        case .privateUse, .sharedCGNAT, .linkLocal, .loopback, .uniqueLocal: true
        default: false
        }
    }

    public static let ipv4: [SpecialPurposeRange] = [
        make("0.0.0.0", 8, .thisNetwork, "This network", "RFC 791"),
        make("10.0.0.0", 8, .privateUse, "Private use", "RFC 1918"),
        make("100.64.0.0", 10, .sharedCGNAT, "Shared address space (CGNAT)", "RFC 6598"),
        make("127.0.0.0", 8, .loopback, "Loopback", "RFC 1122"),
        make("169.254.0.0", 16, .linkLocal, "Link-local", "RFC 3927"),
        make("172.16.0.0", 12, .privateUse, "Private use", "RFC 1918"),
        make("192.0.0.0", 24, .protocolAssignments, "IETF protocol assignments", "RFC 6890"),
        make("192.0.2.0", 24, .documentation, "Documentation", "RFC 5737"),
        make("192.88.99.0", 24, .relayAnycast, "6to4 relay anycast (deprecated)", "RFC 7526"),
        make("192.168.0.0", 16, .privateUse, "Private use", "RFC 1918"),
        make("198.18.0.0", 15, .benchmarking, "Benchmarking", "RFC 2544"),
        make("198.51.100.0", 24, .documentation, "Documentation", "RFC 5737"),
        make("203.0.113.0", 24, .documentation, "Documentation", "RFC 5737"),
        make("224.0.0.0", 4, .multicast, "Multicast", "RFC 5771"),
        make("240.0.0.0", 4, .reserved, "Reserved", "RFC 1112"),
        make("255.255.255.255", 32, .broadcast, "Limited broadcast", "RFC 919"),
    ]

    public static let ipv6: [SpecialPurposeRange] = [
        make("::", 128, .unspecified, "Unspecified address", "RFC 4291"),
        make("::1", 128, .loopback, "Loopback", "RFC 4291"),
        make("::ffff:0:0", 96, .ipv4Mapped, "IPv4-mapped address", "RFC 4291"),
        make("64:ff9b::", 96, .nat64, "NAT64 well-known prefix", "RFC 6052"),
        make("100::", 64, .discard, "Discard-only", "RFC 6666"),
        make("2001::", 32, .teredo, "Teredo", "RFC 4380"),
        make("2001:db8::", 32, .documentation, "Documentation", "RFC 3849"),
        make("2002::", 16, .sixToFour, "6to4", "RFC 3056"),
        make("3fff::", 20, .documentation, "Documentation", "RFC 9637"),
        make("fc00::", 7, .uniqueLocal, "Unique local", "RFC 4193"),
        make("fe80::", 10, .linkLocal, "Link-local", "RFC 4291"),
        make("ff00::", 8, .multicast, "Multicast", "RFC 4291"),
    ]

    private static func make(_ address: String, _ length: Int, _ kind: Kind, _ name: String,
                             _ rfc: String) -> SpecialPurposeRange {
        SpecialPurposeRange(network: IPAddress(address) ?? IPAddress(bytes: [0, 0, 0, 0])!, length: length,
                            kind: kind, name: name, rfc: rfc)
    }

    /// The range containing the whole prefix `network/length`, if any (most specific first).
    public static func containing(_ network: IPAddress, length: Int) -> SpecialPurposeRange? {
        let table = network.family == .v4 ? ipv4 : ipv6
        let candidates = table.filter { range in
            range.length <= length && network.masked(to: range.length) == range.network
        }
        return candidates.max { $0.length < $1.length }
    }
}

public extension IPAddress {
    /// `SpecialPurposeRange.containing(self, length: 32|128)`.
    var specialPurpose: SpecialPurposeRange? {
        SpecialPurposeRange.containing(self, length: bytes.count * 8)
    }
    /// ::ffff:a.b.c.d, 64:ff9b::a.b.c.d, 2002:aabb:ccdd::/48
    var embeddedIPv4: IPAddress? {
        guard bytes.count == 16 else { return nil }
        let head = Array(bytes[0..<12])
        let mapped = [UInt8](repeating: 0, count: 10) + [0xFF, 0xFF]
        let nat64 = [0x00, 0x64, 0xFF, 0x9B] + [UInt8](repeating: 0, count: 8)
        if head == mapped || head == nat64 { return IPAddress(bytes: Array(bytes[12..<16])) }
        if bytes[0] == 0x20, bytes[1] == 0x02 { return IPAddress(bytes: Array(bytes[2..<6])) }
        return nil
    }
    /// The network address of `self/length` (host bits cleared).
    func masked(to length: Int) -> IPAddress {
        let keep = min(max(length, 0), bytes.count * 8)
        var result = bytes
        for index in result.indices {
            let bitsKept = min(max(keep - index * 8, 0), 8)
            let mask: UInt8 = bitsKept == 0 ? 0 : UInt8(truncatingIfNeeded: 0xFF00 >> bitsKept)
            result[index] &= mask
        }
        return IPAddress(bytes: result, scopeID: 0) ?? self
    }
}

public struct ReservedASN: Hashable, Sendable {
    public let range: ClosedRange<UInt32>
    public let name: String            // "Private use", "Documentation", "AS_TRANS"
    public let rfc: String

    public init(range: ClosedRange<UInt32>, name: String, rfc: String) {
        self.range = range
        self.name = name
        self.rfc = rfc
    }

    /// Every reserved block, ascending. Disjoint.
    public static let all: [ReservedASN] = [
        ReservedASN(range: 0...0, name: "Reserved", rfc: "RFC 7607"),
        ReservedASN(range: 23456...23456, name: "AS_TRANS", rfc: "RFC 6793"),
        ReservedASN(range: 64496...64511, name: "Documentation", rfc: "RFC 5398"),
        ReservedASN(range: 64512...65534, name: "Private use", rfc: "RFC 6996"),
        ReservedASN(range: 65535...65535, name: "Reserved", rfc: "RFC 7300"),
        ReservedASN(range: 65536...65551, name: "Documentation", rfc: "RFC 5398"),
        ReservedASN(range: 65552...131071, name: "Reserved by IANA", rfc: "IANA registry"),
        ReservedASN(range: 4_200_000_000...4_294_967_294, name: "Private use", rfc: "RFC 6996"),
        ReservedASN(range: 4_294_967_295...4_294_967_295, name: "Reserved", rfc: "RFC 7300"),
    ]

    public static func lookup(_ asn: UInt32) -> ReservedASN? {
        all.first { $0.range.contains(asn) }
    }
}
