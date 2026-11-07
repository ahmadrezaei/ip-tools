// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct IPAddress: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Family: Sendable, Hashable, Codable { case v4, v6 }

    /// 4 or 16 bytes, network order.
    public let bytes: [UInt8]

    /// IPv6 zone (interface index) for link-local addresses; 0 when unscoped.
    public let scopeID: UInt32

    public var family: Family { bytes.count == 4 ? .v4 : .v6 }

    /// Accepts IPv4/IPv6 literals, "[v6]" and a trailing "%zone".
    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        var scope: UInt32 = 0
        if let pct = s.firstIndex(of: "%") {
            let zone = String(s[s.index(after: pct)...])
            s = String(s[..<pct])
            if let n = UInt32(zone) { scope = n } else if !zone.isEmpty { scope = if_nametoindex(zone) }
        }
        var v4 = in_addr()
        if inet_pton(AF_INET, s, &v4) == 1 {
            self.bytes = withUnsafeBytes(of: &v4) { Array($0) }
            self.scopeID = 0
            return
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, s, &v6) == 1 {
            self.bytes = withUnsafeBytes(of: &v6) { Array($0) }
            self.scopeID = scope
            return
        }
        return nil
    }

    public init?(bytes: [UInt8], scopeID: UInt32 = 0) {
        guard bytes.count == 4 || bytes.count == 16 else { return nil }
        self.bytes = bytes
        self.scopeID = bytes.count == 16 ? scopeID : 0
    }

    /// Builds a `sockaddr_in`/`sockaddr_in6` on the stack and calls `body` with it.
    /// `scopeID` overrides the address's own zone when non-zero.
    func withSockaddr<T>(scopeID override: UInt32 = 0, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) rethrows -> T {
        switch family {
        case .v4:
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            withUnsafeMutableBytes(of: &sin.sin_addr) { $0.copyBytes(from: bytes) }
            return try withUnsafePointer(to: &sin) { p in
                try p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        case .v6:
            var sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            withUnsafeMutableBytes(of: &sin6.sin6_addr) { $0.copyBytes(from: bytes) }
            sin6.sin6_scope_id = override != 0 ? override : scopeID
            return try withUnsafePointer(to: &sin6) { p in
                try p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try body($0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }

    public var description: String {
        var buffer = [CChar](repeating: 0, count: 64)
        let result: UnsafePointer<CChar>? = bytes.withUnsafeBytes { raw in
            inet_ntop(family == .v4 ? AF_INET : AF_INET6, raw.baseAddress, &buffer, 64)
        }
        return result == nil ? "" : String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public var isPubliclyRoutable: Bool { scopeLabel == nil && !isSpecialUse }

    public var scopeLabel: String? {
        switch family {
        case .v4:
            let b = bytes
            if b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168) { return "Private" }
            if b[0] == 100 && (64...127).contains(b[1]) { return "CGNAT" }
            if b[0] == 169 && b[1] == 254 { return "Link-local" }
            if b[0] == 127 { return "Loopback" }
            return nil
        case .v6:
            if bytes == [UInt8](repeating: 0, count: 15) + [1] { return "Loopback" }
            if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return "Link-local" }
            if (bytes[0] & 0xfe) == 0xfc { return "Private" }
            return nil
        }
    }

    private var isSpecialUse: Bool {
        switch family {
        case .v4: return bytes[0] == 0 || bytes[0] >= 224
        case .v6:
            if bytes[0] == 0xff { return true }
            if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0d, bytes[3] == 0xb8 { return true }
            return bytes.allSatisfy { $0 == 0 }
        }
    }

    // Codable as the textual form.
    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let ip = IPAddress(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid IP address"))
        }
        self = ip
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
