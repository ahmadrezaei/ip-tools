// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Range to CIDR helpers (DESIGN §14.9). The public entry point is `WhoisSummarizer.cidrs(fromRange:)`.
/// Internal helpers live here and must not import NetCore: addresses are plain 4 or 16 byte arrays.
enum WhoisRange {
    typealias Bytes = [UInt8]

    // MARK: Parsing and formatting

    static func parseAddress(_ text: String) -> Bytes? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var v4 = in_addr()
        if inet_pton(AF_INET, trimmed, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, trimmed, &v6) == 1 { return withUnsafeBytes(of: &v6) { Array($0) } }
        return nil
    }

    static func format(_ bytes: Bytes) -> String {
        guard bytes.count == 4 || bytes.count == 16 else { return "" }
        var buffer = [CChar](repeating: 0, count: 64)
        let family = bytes.count == 4 ? AF_INET : AF_INET6
        let result: UnsafePointer<CChar>? = bytes.withUnsafeBytes { inet_ntop(family, $0.baseAddress, &buffer, 64) }
        guard result != nil else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// "193.0.0.0/21" -> (bytes with host bits cleared, 21). Nil for anything else.
    static func parseCIDR(_ text: String) -> (bytes: Bytes, length: Int)? {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let bytes = parseAddress(String(parts[0])),
              let length = Int(parts[1].trimmingCharacters(in: .whitespaces)), (0...bytes.count * 8).contains(length)
        else { return nil }
        return (masked(bytes, to: length), length)
    }

    /// "193.0.0.0 - 193.0.7.255" -> (first, last). Both ends must be the same family and ordered.
    static func parseRange(_ text: String) -> (first: Bytes, last: Bytes)? {
        let parts = text.components(separatedBy: " - ")
        guard parts.count == 2, let first = parseAddress(parts[0]), let last = parseAddress(parts[1]),
              first.count == last.count, compare(first, last) <= 0 else { return nil }
        return (first, last)
    }

    /// "2001:4800:: - 2001:49FF:…" -> the same range with canonical (lower-case) addresses; nil if unparsable.
    static func normalizedRange(_ text: String) -> String? {
        guard let range = parseRange(text) else { return nil }
        return "\(format(range.first)) - \(format(range.last))"
    }

    // MARK: Byte arithmetic

    static func masked(_ bytes: Bytes, to length: Int) -> Bytes {
        var result = bytes
        for index in result.indices {
            let kept = min(max(length - index * 8, 0), 8)
            result[index] &= UInt8(truncatingIfNeeded: 0xFF00 >> kept)
        }
        return result
    }

    static func compare(_ a: Bytes, _ b: Bytes) -> Int {
        for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
        return 0
    }

    /// `bytes` with the lowest `bits` bits set to 1.
    private static func filledLow(_ bytes: Bytes, bits: Int) -> Bytes {
        var result = bytes
        for index in result.indices {
            let fromEnd = (result.count - 1 - index) * 8
            let free = min(max(bits - fromEnd, 0), 8)
            result[index] |= UInt8(truncatingIfNeeded: (1 << free) - 1)
        }
        return result
    }

    private static func trailingZeroBits(_ bytes: Bytes) -> Int {
        var count = 0
        for byte in bytes.reversed() {
            if byte == 0 {
                count += 8
            } else {
                return count + byte.trailingZeroBitCount
            }
        }
        return count
    }

    private static func incremented(_ bytes: Bytes) -> Bytes {
        var result = bytes
        for index in result.indices.reversed() {
            if result[index] == 0xFF {
                result[index] = 0
            } else {
                result[index] += 1
                break
            }
        }
        return result
    }

    private static func isAllOnes(_ bytes: Bytes) -> Bool { bytes.allSatisfy { $0 == 0xFF } }

    // MARK: Conversions

    /// Minimal list of CIDR blocks covering exactly `first...last`.
    static func cover(first: Bytes, last: Bytes) -> [String] {
        let bits = first.count * 8
        var result: [String] = []
        var current = first
        while compare(current, last) <= 0 {
            var size = min(trailingZeroBits(current), bits)
            while size > 0, compare(filledLow(current, bits: size), last) > 0 { size -= 1 }
            result.append("\(format(current))/\(bits - size)")
            let end = filledLow(current, bits: size)
            if isAllOnes(end) { break }
            current = incremented(end)
        }
        return result
    }

    /// "193.0.0.0 - 193.0.7.255" or an already-CIDR "193.0.0.0/21" -> CIDR blocks. Empty when unparsable.
    static func cidrs(from text: String) -> [String] {
        if let range = parseRange(text) { return cover(first: range.first, last: range.last) }
        if let cidr = parseCIDR(text) { return ["\(format(cidr.bytes))/\(cidr.length)"] }
        return []
    }

    /// The first and last address of a CIDR block as "a - b".
    static func range(fromCIDR text: String) -> String? {
        guard let cidr = parseCIDR(text) else { return nil }
        let last = filledLow(cidr.bytes, bits: cidr.bytes.count * 8 - cidr.length)
        return "\(format(cidr.bytes)) - \(format(last))"
    }

    /// Prefix length of a CIDR, or of the smallest block enclosing a range (common leading bits).
    static func prefixLength(of text: String) -> Int? {
        if let cidr = parseCIDR(text) { return cidr.length }
        guard let range = parseRange(text) else { return nil }
        var length = 0
        for (x, y) in zip(range.first, range.last) {
            if x == y {
                length += 8
            } else {
                return length + (x ^ y).leadingZeroBitCount
            }
        }
        return length
    }

    static func isIPv6(_ text: String) -> Bool { text.contains(":") }

    /// Does the route (a CIDR) contain `prefix` or equal it?
    static func route(_ route: String, covers prefix: (bytes: Bytes, length: Int)) -> Bool {
        guard let candidate = parseCIDR(route), candidate.bytes.count == prefix.bytes.count,
              candidate.length <= prefix.length else { return false }
        return masked(prefix.bytes, to: candidate.length) == candidate.bytes
    }
}
