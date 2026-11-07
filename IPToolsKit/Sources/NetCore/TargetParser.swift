// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum Target: Hashable, Sendable {
    case ip(IPAddress)
    case hostname(String)
    case prefix(IPAddress, length: Int)             // BGP only
    case asn(UInt32)                                // BGP only
}

public enum TargetParser {
    public enum Mode: Sendable { case host, bgp }   // .host = Ping/Trace (ip|hostname), .bgp = all four

    /// Trims, strips URL scheme/path, brackets. (Minimal stub implementation; NetCore owner refines.)
    public static func parse(_ raw: String, mode: Mode) -> Target? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/"), !(mode == .bgp && IPAddress(String(s[..<slash])) != nil) {
            s = String(s[..<slash])
        }
        guard !s.isEmpty else { return nil }
        if mode == .bgp {
            let upper = s.uppercased()
            let digits = upper.hasPrefix("AS") ? String(upper.dropFirst(2)) : upper
            if upper.hasPrefix("AS"), let n = UInt32(digits) { return .asn(n) }
            if let slash = s.firstIndex(of: "/"),
               let ip = IPAddress(String(s[..<slash])),
               let len = Int(s[s.index(after: slash)...]),
               len >= 0, len <= (ip.family == .v4 ? 32 : 128) {
                return .prefix(ip, length: len)
            }
        }
        if let ip = IPAddress(s) { return .ip(ip) }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return .hostname(s)
    }

    /// Key used for recents.
    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
