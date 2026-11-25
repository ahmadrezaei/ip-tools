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
    public static func current() -> [LocalAddress] {
        assemble(rawAddresses())
    }

    /// Kind by BSD name: `en0` Wi-Fi, `pdp_ip*` cellular, other `en*` wired, `utun*` VPN only when the
    /// interface has a non-link-local address (iOS keeps idle `utun` interfaces), anything else `.other`.
    static func classify(name: String, hasNonLinkLocal: Bool) -> LocalAddress.Interface {
        if name == "en0" { return .wifi }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name.hasPrefix("en") { return .wired }
        if name.hasPrefix("utun") { return hasNonLinkLocal ? .vpn : .other }
        return .other
    }

    /// Filters, classifies and sorts raw (interface name, address) pairs. Pure, so it is unit-tested.
    static func assemble(_ raw: [(name: String, address: IPAddress)]) -> [LocalAddress] {
        let kept = raw.filter { keep($0.address) }
        let usable = Dictionary(grouping: kept, by: \.name)
        let result = kept.map { entry -> LocalAddress in
            let hasNonLinkLocal = usable[entry.name, default: []].contains { !isLinkLocal($0.address) }
            let kind = classify(name: entry.name, hasNonLinkLocal: hasNonLinkLocal)
            return LocalAddress(interface: kind, name: entry.name, address: entry.address)
        }
        return result.sorted { lhs, rhs in
            let l = (rank(lhs.interface), lhs.address.family == .v4 ? 0 : 1, lhs.name, lhs.address.description)
            let r = (rank(rhs.interface), rhs.address.family == .v4 ? 0 : 1, rhs.name, rhs.address.description)
            return l < r
        }
    }

    private static func rank(_ interface: LocalAddress.Interface) -> Int {
        switch interface {
        case .wifi: 0
        case .cellular: 1
        case .wired: 2
        case .vpn: 3
        case .other: 4
        }
    }

    private static func isLinkLocal(_ address: IPAddress) -> Bool {
        address.specialPurpose?.kind == .linkLocal
    }

    /// IPv4 except link-local; IPv6 only global unicast (2000::/3) or unique local (fc00::/7).
    private static func keep(_ address: IPAddress) -> Bool {
        guard address.family == .v6 else { return !isLinkLocal(address) }
        let first = address.bytes[0]
        return (first & 0xE0) == 0x20 || (first & 0xFE) == 0xFC
    }

    private static func rawAddresses() -> [(name: String, address: IPAddress)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [(name: String, address: IPAddress)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        let required = UInt32(IFF_UP | IFF_RUNNING)
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = UInt32(entry.pointee.ifa_flags)
            guard flags & required == required, flags & UInt32(IFF_LOOPBACK) == 0,
                  let sa = entry.pointee.ifa_addr, let address = address(from: sa) else { continue }
            result.append((String(cString: entry.pointee.ifa_name), address))
        }
        return result
    }

    private static func address(from sa: UnsafePointer<sockaddr>) -> IPAddress? {
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin_addr) { IPAddress(bytes: Array($0)) }
            }
        case AF_INET6:
            return sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin6_addr) { IPAddress(bytes: Array($0)) }
            }
        default:
            return nil
        }
    }
}
