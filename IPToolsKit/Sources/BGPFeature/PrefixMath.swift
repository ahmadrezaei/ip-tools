// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore

/// Address arithmetic for choosing the traceroute probe target of a prefix (DESIGN 6.11.5).
enum PrefixMath {
    /// "8.8.8.0/24" -> 8.8.8.1; IPv4 /31 and /32 -> the network address itself; IPv6 -> network + 1 (the address itself for /128).
    static func probeAddress(forPrefix prefix: String) -> IPAddress? {
        let parts = prefix.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let base = IPAddress(parts[0]), let length = Int(parts[1]) else { return nil }
        let bits = base.bytes.count * 8
        guard (0...bits).contains(length) else { return nil }
        var bytes = base.bytes
        for index in bytes.indices {
            let kept = max(0, min(8, length - index * 8))
            let mask: UInt8 = kept == 0 ? 0 : UInt8(truncatingIfNeeded: 0xFF << (8 - kept))
            bytes[index] &= mask
        }
        let hostBits = bits - length
        let useNetwork = base.family == .v4 ? length >= 31 : hostBits == 0
        if !useNetwork {
            var index = bytes.count - 1
            while index >= 0 {
                if bytes[index] == 255 { bytes[index] = 0; index -= 1 } else { bytes[index] += 1; break }
            }
        }
        return IPAddress(bytes: bytes)
    }
}
