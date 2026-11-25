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
    public var cidr: String { fatalError("TODO") }
    /// Ping/trace sensible: private, CGNAT, link-local, loopback, ULA.
    public var allowsProbing: Bool { fatalError("TODO") }
    public static var ipv4: [SpecialPurposeRange] { [] }
    public static var ipv6: [SpecialPurposeRange] { [] }

    /// The range containing the whole prefix `network/length`, if any (most specific first).
    public static func containing(_ network: IPAddress, length: Int) -> SpecialPurposeRange? { fatalError("TODO") }
}

public extension IPAddress {
    /// `SpecialPurposeRange.containing(self, length: 32|128)`.
    var specialPurpose: SpecialPurposeRange? { fatalError("TODO") }
    /// ::ffff:a.b.c.d, 64:ff9b::a.b.c.d, 2002:aabb:ccdd::/48
    var embeddedIPv4: IPAddress? { fatalError("TODO") }
    /// The network address of `self/length` (host bits cleared).
    func masked(to length: Int) -> IPAddress { fatalError("TODO") }
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

    public static func lookup(_ asn: UInt32) -> ReservedASN? { fatalError("TODO") }
}
