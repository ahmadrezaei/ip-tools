// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct LocalAddress: Hashable, Sendable, Identifiable {
    public enum Interface: Hashable, Sendable { case wifi, cellular, wired, vpn, other }

    public let interface: Interface
    public let name: String            // BSD name, "en0"
    public let address: IPAddress
    public var id: String { "\(name)|\(address)" }

    public init(interface: Interface, name: String, address: IPAddress) {
        self.interface = interface
        self.name = name
        self.address = address
    }
}

public enum LocalInterfaces {
    /// getifaddrs; up+running, non-loopback; IPv4 + global/ULA IPv6. Sorted Wi-Fi, cellular, wired, VPN, other; v4 before v6.
    public static func current() -> [LocalAddress] { [] }

    static func classify(name: String, hasNonLinkLocal: Bool) -> LocalAddress.Interface { fatalError("TODO") }
}
