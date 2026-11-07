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

    /// Trims; strips URL scheme, userinfo, port, path/query/fragment, brackets and a trailing dot.
    public static func parse(_ raw: String, mode: Mode) -> Target? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let end = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<end]) }

        // Prefix notation (BGP): "1.1.1.0/24", "2606:4700::/32".
        if mode == .bgp, let slash = s.firstIndex(of: "/"),
           let ip = IPAddress(String(s[..<slash])),
           let len = Int(s[s.index(after: slash)...]),
           len >= 0, len <= (ip.family == .v4 ? 32 : 128) {
            return .prefix(ip, length: len)
        }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        guard !s.isEmpty else { return nil }

        if mode == .bgp {
            let upper = s.uppercased()
            let digits = upper.dropFirst(2)
            if upper.hasPrefix("AS"), !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return UInt32(digits).map { .asn($0) }
            }
            if s.allSatisfy({ $0.isASCII && $0.isNumber }), let n = UInt32(s) { return .asn(n) }
        }

        // Bracketed IPv6, optionally with a port.
        if s.hasPrefix("[") {
            guard let close = s.firstIndex(of: "]") else { return nil }
            let inner = String(s[s.index(after: s.startIndex)..<close])
            let rest = s[s.index(after: close)...]
            guard rest.isEmpty || (rest.hasPrefix(":") && rest.dropFirst().allSatisfy(\.isNumber)) else { return nil }
            guard let ip = IPAddress(inner), ip.family == .v6 else { return nil }
            return .ip(ip)
        }
        if let ip = IPAddress(s) { return .ip(ip) }

        // "host:port" (a single colon; anything else would have been an IPv6 literal).
        if s.filter({ $0 == ":" }).count == 1, let colon = s.firstIndex(of: ":") {
            let port = s[s.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return nil }
            s = String(s[..<colon])
            if let ip = IPAddress(s), ip.family == .v4 { return .ip(ip) }
        }
        if s.hasSuffix(".") { s.removeLast() }
        return isValidHostname(s) ? .hostname(s) : nil
    }

    /// Key used for recents.
    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isValidHostname(_ s: String) -> Bool {
        guard !s.isEmpty, s.utf8.count <= 253 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            guard !label.isEmpty, label.utf8.count <= 63,
                  label.unicodeScalars.allSatisfy({ allowed.contains($0) }),
                  !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
        }
        // A numeric last label means a malformed IPv4 address ("1.2.3", "1.1.1.256"), not a name.
        if let last = labels.last, last.allSatisfy(\.isNumber) { return false }
        return true
    }
}
