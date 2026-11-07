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

    /// Strips the IPv4 header when present; returns message + IPv4 TTL if available.
    /// Returns nil for truncated or malformed datagrams and for IPv4 messages with a bad checksum.
    public static func parse(_ datagram: [UInt8], family: IPAddress.Family) -> (message: ICMPMessage, ttl: Int?)? {
        var offset = 0
        var ttl: Int?
        if family == .v4, let first = datagram.first, first >> 4 == 4 {
            // Darwin delivers the IPv4 header on ICMP datagram sockets.
            let ihl = Int(first & 0x0f) * 4
            guard ihl >= 20, datagram.count >= ihl + 8 else { return nil }
            if datagram[9] != 1 { return nil }
            ttl = Int(datagram[8])
            offset = ihl
        }
        guard datagram.count - offset >= 8 else { return nil }
        let msg = offset == 0 ? datagram : Array(datagram[offset...])
        let type = msg[0], code = msg[1]
        // Darwin rewrites the quoted header inside Time Exceeded / Unreachable messages before delivery,
        // so their checksum no longer verifies. Verify everything else.
        if family == .v4, type != 11, type != 3, checksum(msg) != 0 { return nil }

        switch (family, type) {
        case (.v4, 0), (.v6, 129):
            let id = UInt16(msg[4]) << 8 | UInt16(msg[5])
            let seq = UInt16(msg[6]) << 8 | UInt16(msg[7])
            return (.echoReply(identifier: id, sequence: seq, payload: Array(msg[8...])), ttl)
        case (.v4, 11), (.v6, 3):
            return (.timeExceeded(quotedEcho(msg, family: family)), ttl)
        case (.v4, 3), (.v6, 1):
            return (.destinationUnreachable(code: code, quotedEcho(msg, family: family)), ttl)
        default:
            return (.other(type: type, code: code), ttl)
        }
    }

    /// Extracts the identifier/sequence of the echo request quoted inside an error message.
    private static func quotedEcho(_ msg: [UInt8], family: IPAddress.Family) -> QuotedEcho? {
        let inner = 8   // error messages carry 4 unused bytes after the 4-byte ICMP header
        guard msg.count > inner else { return nil }
        let icmpStart: Int
        switch family {
        case .v4:
            guard msg[inner] >> 4 == 4 else { return nil }
            let ihl = Int(msg[inner] & 0x0f) * 4
            guard ihl >= 20, msg.count >= inner + ihl + 8, msg[inner + 9] == 1 else { return nil }
            icmpStart = inner + ihl
            guard msg[icmpStart] == 8 else { return nil }
        case .v6:
            guard msg.count >= inner + 40 + 8, msg[inner] >> 4 == 6, msg[inner + 6] == 58 else { return nil }
            icmpStart = inner + 40
            guard msg[icmpStart] == 128 else { return nil }
        }
        return QuotedEcho(identifier: UInt16(msg[icmpStart + 4]) << 8 | UInt16(msg[icmpStart + 5]),
                          sequence: UInt16(msg[icmpStart + 6]) << 8 | UInt16(msg[icmpStart + 7]))
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
