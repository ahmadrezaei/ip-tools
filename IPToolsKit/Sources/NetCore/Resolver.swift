// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum AddressPreference: String, Codable, Sendable, CaseIterable { case automatic, ipv4, ipv6 }

public struct ResolvedTarget: Hashable, Sendable {
    public let input: String                        // what the user typed (trimmed)
    public let address: IPAddress                   // the address that will be probed
    public let hostname: String?                    // nil if input was an IP literal
    public let allAddresses: [IPAddress]

    public init(input: String, address: IPAddress, hostname: String?, allAddresses: [IPAddress]) {
        self.input = input
        self.address = address
        self.hostname = hostname
        self.allAddresses = allAddresses
    }
}

public enum Resolver {
    /// Literal IPs return immediately; hostnames use getaddrinfo(AI_ADDRCONFIG) off the main thread.
    /// Stub: hostnames are not yet implemented.
    public static func resolve(_ input: String, preference: AddressPreference) async throws -> ResolvedTarget {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ip = IPAddress(trimmed) {
            return ResolvedTarget(input: trimmed, address: ip, hostname: nil, allAddresses: [ip])
        }
        throw NetError.resolutionFailed(host: trimmed, reason: "not implemented")
    }

    /// getnameinfo(NI_NAMEREQD) raced against `timeout`; nil on failure or timeout. Stub: returns nil.
    public static func reverseName(for address: IPAddress, timeout: Duration = .seconds(2)) async -> String? {
        nil
    }
}
