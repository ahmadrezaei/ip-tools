// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct IPAddress: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Family: Sendable, Hashable, Codable { case v4, v6 }

    /// 4 or 16 bytes, network order.
    public let bytes: [UInt8]

    public var family: Family { bytes.count == 4 ? .v4 : .v6 }

    /// Accepts IPv4/IPv6 literals, "[v6]" and a trailing "%zone".
    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
        var v4 = in_addr()
        if inet_pton(AF_INET, s, &v4) == 1 {
            self.bytes = withUnsafeBytes(of: &v4) { Array($0) }
            return
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, s, &v6) == 1 {
            self.bytes = withUnsafeBytes(of: &v6) { Array($0) }
            return
        }
        return nil
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count == 4 || bytes.count == 16 else { return nil }
        self.bytes = bytes
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
