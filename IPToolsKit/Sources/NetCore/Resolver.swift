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
    public static func resolve(_ input: String, preference: AddressPreference) async throws -> ResolvedTarget {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = TargetParser.parse(trimmed, mode: .host) else { throw NetError.invalidTarget(trimmed) }
        switch parsed {
        case let .ip(ip):
            return ResolvedTarget(input: trimmed, address: ip, hostname: nil, allAddresses: [ip])
        case let .hostname(host):
            let addresses = try await lookup(host, preference: preference)
            return ResolvedTarget(input: trimmed, address: addresses[0], hostname: host, allAddresses: addresses)
        case .prefix, .asn:
            throw NetError.invalidTarget(trimmed)
        }
    }

    /// getnameinfo(NI_NAMEREQD) raced against `timeout`; nil on failure or timeout.
    public static func reverseName(for address: IPAddress, timeout: Duration = .seconds(2)) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                once.resume(with: blockingReverse(address))
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout.seconds) {
                once.resume(with: nil)
            }
        }
    }

    // MARK: - Private

    private static func lookup(_ host: String, preference: AddressPreference) async throws -> [IPAddress] {
        let family: Int32 = switch preference {
        case .automatic: AF_UNSPEC
        case .ipv4: AF_INET
        case .ipv6: AF_INET6
        }
        let result: Result<[IPAddress], NetError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: blockingLookup(host, family: family, preference: preference))
            }
        }
        return try result.get()
    }

    private static func blockingLookup(_ host: String, family: Int32, preference: AddressPreference) -> Result<[IPAddress], NetError> {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = AI_ADDRCONFIG
        var head: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, nil, &hints, &head)
        guard rc == 0, let first = head else {
            if preference != .automatic, rc == EAI_NONAME || rc == EAI_NODATA || rc == EAI_ADDRFAMILY || rc == EAI_FAMILY {
                return .failure(.noAddress(host: host, family: preference == .ipv4 ? .v4 : .v6))
            }
            return .failure(.resolutionFailed(host: host, reason: String(validatingCString: gai_strerror(rc)) ?? "error \(rc)"))
        }
        defer { freeaddrinfo(first) }
        var out: [IPAddress] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let ai = cursor {
            if let sa = ai.pointee.ai_addr {
                var ip: IPAddress?
                if ai.pointee.ai_family == AF_INET {
                    ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { p in
                        IPAddress(bytes: withUnsafeBytes(of: p.pointee.sin_addr) { Array($0) })
                    }
                } else if ai.pointee.ai_family == AF_INET6 {
                    ip = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p in
                        IPAddress(bytes: withUnsafeBytes(of: p.pointee.sin6_addr) { Array($0) })
                    }
                }
                if let ip, !out.contains(ip) { out.append(ip) }
            }
            cursor = ai.pointee.ai_next
        }
        guard !out.isEmpty else {
            return .failure(.resolutionFailed(host: host, reason: "No usable address"))
        }
        return .success(out)
    }

    private static func blockingReverse(_ address: IPAddress) -> String? {
        var storage = sockaddr_storage()
        let length: socklen_t
        switch address.family {
        case .v4:
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            withUnsafeMutableBytes(of: &sin.sin_addr) { $0.copyBytes(from: address.bytes) }
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: &sin) { $0 }) }
            length = socklen_t(MemoryLayout<sockaddr_in>.size)
        case .v6:
            var sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            withUnsafeMutableBytes(of: &sin6.sin6_addr) { $0.copyBytes(from: address.bytes) }
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: &sin6) { $0 }) }
            length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = withUnsafePointer(to: &storage) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(sa, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard rc == 0 else { return nil }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }
}

/// Resumes a continuation exactly once; later calls are ignored.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }

    func resume(with value: String?) {
        let c = lock.withLock { () -> CheckedContinuation<String?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        c?.resume(returning: value)
    }
}
