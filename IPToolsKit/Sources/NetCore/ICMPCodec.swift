// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public struct QuotedEcho: Sendable, Equatable {
    public let identifier: UInt16
    public let sequence: UInt16
    public init(identifier: UInt16, sequence: UInt16) {
        self.identifier = identifier
        self.sequence = sequence
    }
}

public enum ICMPMessage: Sendable, Equatable {
    case echoReply(identifier: UInt16, sequence: UInt16, payload: [UInt8])
    case timeExceeded(QuotedEcho?)
    case destinationUnreachable(code: UInt8, QuotedEcho?)
    case other(type: UInt8, code: UInt8)
}

public enum ICMPCodec {
    public static func echoRequest(family: IPAddress.Family, identifier: UInt16, sequence: UInt16, payload: [UInt8]) -> [UInt8] {
        var packet: [UInt8] = [family == .v4 ? 8 : 128, 0, 0, 0,
                               UInt8(identifier >> 8), UInt8(identifier & 0xff),
                               UInt8(sequence >> 8), UInt8(sequence & 0xff)]
        packet.append(contentsOf: payload)
        if family == .v4 {   // ICMPv6 checksum is filled in by the kernel
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xff)
        }
        return packet
    }

    /// Strips the IPv4 header when present; returns message + IPv4 TTL if available. Stub: returns nil.
    public static func parse(_ datagram: [UInt8], family: IPAddress.Family) -> (message: ICMPMessage, ttl: Int?)? {
        nil
    }

    /// RFC 1071 internet checksum.
    public static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }
}
