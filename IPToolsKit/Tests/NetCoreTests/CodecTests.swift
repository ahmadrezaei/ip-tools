// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Testing
@testable import NetCore

private func fixChecksum(_ msg: [UInt8]) -> [UInt8] {
    var m = msg
    m[2] = 0; m[3] = 0
    let c = ICMPCodec.checksum(m)
    m[2] = UInt8(c >> 8); m[3] = UInt8(c & 0xff)
    return m
}

private func ipv4Header(ihl: Int = 5, proto: UInt8 = 1, ttl: UInt8 = 57, totalLength: Int) -> [UInt8] {
    var h = [UInt8](repeating: 0, count: ihl * 4)
    h[0] = 0x40 | UInt8(ihl)
    h[2] = UInt8(totalLength >> 8); h[3] = UInt8(totalLength & 0xff)
    h[8] = ttl; h[9] = proto
    h[12...15] = [10, 0, 0, 1]; h[16...19] = [10, 0, 0, 2]
    if ihl > 5 { h[20] = 1 }   // NOP option
    return h
}

private let echoOut: [UInt8] = ICMPCodec.echoRequest(family: .v4, identifier: 0xABCD, sequence: 0x0102, payload: [1, 2, 3, 4, 5, 6, 7, 8])

@Suite struct ICMPCodecTests {
    @Test func echoRequestLayout() {
        let p = ICMPCodec.echoRequest(family: .v4, identifier: 0x1234, sequence: 7, payload: [9, 9])
        #expect(Array(p[0..<2]) == [8, 0])
        #expect(Array(p[4..<8]) == [0x12, 0x34, 0, 7])
        #expect(ICMPCodec.checksum(p) == 0)   // a valid message sums to zero
        let p6 = ICMPCodec.echoRequest(family: .v6, identifier: 1, sequence: 2, payload: [])
        #expect(p6 == [128, 0, 0, 0, 0, 1, 0, 2])
    }

    @Test func checksumRFC1071Example() {
        // Example from RFC 1071 §3: sum of 00 01 f2 03 f4 f5 f6 f7 is ddf2, checksum 220d.
        #expect(ICMPCodec.checksum([0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7]) == 0x220d)
        #expect(ICMPCodec.checksum([0x01]) == 0xfeff)   // odd length is padded with zero
    }

    @Test(arguments: [5, 6]) func echoReplyV4(ihl: Int) throws {
        var reply = [0, 0, 0, 0, 0xAB, 0xCD, 0x01, 0x02, 1, 2, 3, 4, 5, 6, 7, 8] as [UInt8]
        reply = fixChecksum(reply)
        let datagram = ipv4Header(ihl: ihl, ttl: 57, totalLength: ihl * 4 + reply.count) + reply
        let parsed = try #require(ICMPCodec.parse(datagram, family: .v4))
        #expect(parsed.message == .echoReply(identifier: 0xABCD, sequence: 0x0102, payload: [1, 2, 3, 4, 5, 6, 7, 8]))
        #expect(parsed.ttl == 57)
    }

    @Test func echoReplyWithoutIPHeader() throws {
        let reply = fixChecksum([0, 0, 0, 0, 0, 1, 0, 2, 0xAA])
        let parsed = try #require(ICMPCodec.parse(reply, family: .v4))
        #expect(parsed.message == .echoReply(identifier: 1, sequence: 2, payload: [0xAA]))
        #expect(parsed.ttl == nil)
    }

    @Test func badChecksumRejected() {
        var reply = fixChecksum([0, 0, 0, 0, 0xAB, 0xCD, 0x01, 0x02, 1, 2, 3, 4])
        reply[8] ^= 0xff
        #expect(ICMPCodec.parse(ipv4Header(totalLength: 20 + reply.count) + reply, family: .v4) == nil)
    }

    @Test func truncatedRejected() {
        #expect(ICMPCodec.parse([], family: .v4) == nil)
        #expect(ICMPCodec.parse([0, 0, 0], family: .v4) == nil)
        #expect(ICMPCodec.parse([0x45, 0, 0], family: .v4) == nil)
        #expect(ICMPCodec.parse([129, 0, 0, 0], family: .v6) == nil)
    }

    @Test(arguments: [5, 6]) func timeExceededV4QuotesEcho(outerIHL: Int) throws {
        for innerIHL in [5, 6] {
            let quoted = ipv4Header(ihl: innerIHL, ttl: 1, totalLength: innerIHL * 4 + echoOut.count) + echoOut
            // Checksum is not verified for error messages (Darwin rewrites the quoted header).
            let msg: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + quoted
            let datagram = ipv4Header(ihl: outerIHL, ttl: 250, totalLength: outerIHL * 4 + msg.count) + msg
            let parsed = try #require(ICMPCodec.parse(datagram, family: .v4))
            #expect(parsed.message == .timeExceeded(QuotedEcho(identifier: 0xABCD, sequence: 0x0102)))
            #expect(parsed.ttl == 250)
        }
    }

    @Test func destinationUnreachableV4() throws {
        let quoted = ipv4Header(ttl: 1, totalLength: 20 + 8) + Array(echoOut.prefix(8))
        let msg: [UInt8] = [3, 1, 0, 0, 0, 0, 0, 0] + quoted
        let parsed = try #require(ICMPCodec.parse(ipv4Header(totalLength: 20 + msg.count) + msg, family: .v4))
        #expect(parsed.message == .destinationUnreachable(code: 1, QuotedEcho(identifier: 0xABCD, sequence: 0x0102)))
    }

    @Test func errorWithoutEnoughQuotedBytesHasNoQuote() throws {
        let quoted = ipv4Header(ttl: 1, totalLength: 28) + [8, 0, 0, 0]   // only 4 bytes of ICMP
        let msg: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + quoted
        let parsed = try #require(ICMPCodec.parse(ipv4Header(totalLength: 20 + msg.count) + msg, family: .v4))
        #expect(parsed.message == .timeExceeded(nil))
    }

    @Test func quotedNonEchoIsNotMatched() throws {
        let udp: [UInt8] = [0x30, 0x39, 0, 53, 0, 8, 0, 0]
        let quoted = ipv4Header(proto: 17, ttl: 1, totalLength: 28) + udp
        let msg: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + quoted
        let parsed = try #require(ICMPCodec.parse(ipv4Header(totalLength: 20 + msg.count) + msg, family: .v4))
        #expect(parsed.message == .timeExceeded(nil))
    }

    @Test func otherTypePassesThrough() throws {
        let msg = fixChecksum([8, 0, 0, 0, 0, 1, 0, 1])   // someone else's echo request
        let parsed = try #require(ICMPCodec.parse(ipv4Header(totalLength: 28) + msg, family: .v4))
        #expect(parsed.message == .other(type: 8, code: 0))
    }

    // MARK: IPv6 (no IP header on receive; kernel handles the checksum)

    @Test func echoReplyV6() throws {
        let msg: [UInt8] = [129, 0, 0x12, 0x34, 0, 5, 0, 9, 0xDE, 0xAD]
        let parsed = try #require(ICMPCodec.parse(msg, family: .v6))
        #expect(parsed.message == .echoReply(identifier: 5, sequence: 9, payload: [0xDE, 0xAD]))
        #expect(parsed.ttl == nil)
    }

    @Test func timeExceededV6() throws {
        let echo6 = ICMPCodec.echoRequest(family: .v6, identifier: 0x7777, sequence: 3, payload: [1, 2, 3, 4])
        var inner = [UInt8](repeating: 0, count: 40)
        inner[0] = 0x60; inner[6] = 58; inner[7] = 1
        let msg: [UInt8] = [3, 0, 0, 0, 0, 0, 0, 0] + inner + echo6
        let parsed = try #require(ICMPCodec.parse(msg, family: .v6))
        #expect(parsed.message == .timeExceeded(QuotedEcho(identifier: 0x7777, sequence: 3)))
    }

    @Test func destinationUnreachableV6() throws {
        let echo6 = ICMPCodec.echoRequest(family: .v6, identifier: 0x7777, sequence: 4, payload: [])
        var inner = [UInt8](repeating: 0, count: 40)
        inner[0] = 0x60; inner[6] = 58
        let msg: [UInt8] = [1, 3, 0, 0, 0, 0, 0, 0] + inner + echo6
        let parsed = try #require(ICMPCodec.parse(msg, family: .v6))
        #expect(parsed.message == .destinationUnreachable(code: 3, QuotedEcho(identifier: 0x7777, sequence: 4)))
    }

    @Test func v6TooBigIsOther() throws {
        let parsed = try #require(ICMPCodec.parse([2, 0, 0, 0, 0, 0, 5, 0], family: .v6))
        #expect(parsed.message == .other(type: 2, code: 0))
    }
}
