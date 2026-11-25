// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Testing
@testable import NetCore

private func ip(_ text: String) -> IPAddress { IPAddress(text)! }

/// First address, last address, and the neighbours just outside each end.
private struct RangeCase: Sendable, CustomTestStringConvertible {
    let cidr: String
    let first: String
    let last: String
    let before: String?
    let after: String?
    let kind: SpecialPurposeRange.Kind
    var testDescription: String { cidr }
}

private let v4Cases: [RangeCase] = [
    RangeCase(cidr: "0.0.0.0/8", first: "0.0.0.0", last: "0.255.255.255", before: nil, after: "1.0.0.0",
              kind: .thisNetwork),
    RangeCase(cidr: "10.0.0.0/8", first: "10.0.0.0", last: "10.255.255.255", before: "9.255.255.255",
              after: "11.0.0.0", kind: .privateUse),
    RangeCase(cidr: "100.64.0.0/10", first: "100.64.0.0", last: "100.127.255.255", before: "100.63.255.255",
              after: "100.128.0.0", kind: .sharedCGNAT),
    RangeCase(cidr: "127.0.0.0/8", first: "127.0.0.0", last: "127.255.255.255", before: "126.255.255.255",
              after: "128.0.0.0", kind: .loopback),
    RangeCase(cidr: "169.254.0.0/16", first: "169.254.0.0", last: "169.254.255.255", before: "169.253.255.255",
              after: "169.255.0.0", kind: .linkLocal),
    RangeCase(cidr: "172.16.0.0/12", first: "172.16.0.0", last: "172.31.255.255", before: "172.15.255.255",
              after: "172.32.0.0", kind: .privateUse),
    RangeCase(cidr: "192.0.0.0/24", first: "192.0.0.0", last: "192.0.0.255", before: "191.255.255.255",
              after: "192.0.1.0", kind: .protocolAssignments),
    RangeCase(cidr: "192.0.2.0/24", first: "192.0.2.0", last: "192.0.2.255", before: "192.0.1.255",
              after: "192.0.3.0", kind: .documentation),
    RangeCase(cidr: "192.88.99.0/24", first: "192.88.99.0", last: "192.88.99.255", before: "192.88.98.255",
              after: "192.88.100.0", kind: .relayAnycast),
    RangeCase(cidr: "192.168.0.0/16", first: "192.168.0.0", last: "192.168.255.255", before: "192.167.255.255",
              after: "192.169.0.0", kind: .privateUse),
    RangeCase(cidr: "198.18.0.0/15", first: "198.18.0.0", last: "198.19.255.255", before: "198.17.255.255",
              after: "198.20.0.0", kind: .benchmarking),
    RangeCase(cidr: "198.51.100.0/24", first: "198.51.100.0", last: "198.51.100.255", before: "198.51.99.255",
              after: "198.51.101.0", kind: .documentation),
    RangeCase(cidr: "203.0.113.0/24", first: "203.0.113.0", last: "203.0.113.255", before: "203.0.112.255",
              after: "203.0.114.0", kind: .documentation),
    RangeCase(cidr: "224.0.0.0/4", first: "224.0.0.0", last: "239.255.255.255", before: "223.255.255.255",
              after: "240.0.0.0", kind: .multicast),
    RangeCase(cidr: "240.0.0.0/4", first: "240.0.0.0", last: "255.255.255.254", before: "239.255.255.255",
              after: nil, kind: .reserved),
    RangeCase(cidr: "255.255.255.255/32", first: "255.255.255.255", last: "255.255.255.255",
              before: "255.255.255.254", after: nil, kind: .broadcast),
]

private let v6Cases: [RangeCase] = [
    RangeCase(cidr: "::/128", first: "::", last: "::", before: nil, after: "::2", kind: .unspecified),
    RangeCase(cidr: "::1/128", first: "::1", last: "::1", before: nil, after: "::2", kind: .loopback),
    RangeCase(cidr: "::ffff:0.0.0.0/96", first: "::ffff:0.0.0.0", last: "::ffff:255.255.255.255",
              before: "::fffe:ffff:ffff", after: "::1:0:0:0", kind: .ipv4Mapped),
    RangeCase(cidr: "64:ff9b::/96", first: "64:ff9b::", last: "64:ff9b::ffff:ffff",
              before: "64:ff9a:ffff:ffff:ffff:ffff:ffff:ffff", after: "64:ff9b::1:0:0", kind: .nat64),
    RangeCase(cidr: "100::/64", first: "100::", last: "100::ffff:ffff:ffff:ffff",
              before: "ff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", after: "100:0:0:1::", kind: .discard),
    RangeCase(cidr: "2001::/32", first: "2001::", last: "2001:0:ffff:ffff:ffff:ffff:ffff:ffff",
              before: "2000:ffff:ffff:ffff:ffff:ffff:ffff:ffff", after: "2001:1::", kind: .teredo),
    RangeCase(cidr: "2001:db8::/32", first: "2001:db8::", last: "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff",
              before: "2001:db7:ffff:ffff:ffff:ffff:ffff:ffff", after: "2001:db9::", kind: .documentation),
    RangeCase(cidr: "2002::/16", first: "2002::", last: "2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
              before: "2001:ffff:ffff:ffff:ffff:ffff:ffff:ffff", after: "2003::", kind: .sixToFour),
    RangeCase(cidr: "3fff::/20", first: "3fff::", last: "3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff",
              before: "3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff", after: "3fff:1000::", kind: .documentation),
    RangeCase(cidr: "fc00::/7", first: "fc00::", last: "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
              before: "fbff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", after: "fe00::", kind: .uniqueLocal),
    RangeCase(cidr: "fe80::/10", first: "fe80::", last: "febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
              before: "fe7f:ffff:ffff:ffff:ffff:ffff:ffff:ffff", after: "fec0::", kind: .linkLocal),
    RangeCase(cidr: "ff00::/8", first: "ff00::", last: "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
              before: "feff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", after: nil, kind: .multicast),
]

@Suite struct SpecialPurposeTests {
    private func check(_ c: RangeCase, in table: [SpecialPurposeRange]) {
        let range = table.first { $0.cidr == c.cidr }
        #expect(range?.kind == c.kind)
        #expect(ip(c.first).specialPurpose?.cidr == c.cidr)
        #expect(ip(c.last).specialPurpose?.cidr == c.cidr)
        if let before = c.before { #expect(ip(before).specialPurpose?.cidr != c.cidr) }
        if let after = c.after { #expect(ip(after).specialPurpose?.cidr != c.cidr) }
    }

    @Test(arguments: v4Cases)
    private func ipv4Boundaries(_ c: RangeCase) {
        check(c, in: SpecialPurposeRange.ipv4)
    }

    @Test(arguments: v6Cases)
    private func ipv6Boundaries(_ c: RangeCase) {
        check(c, in: SpecialPurposeRange.ipv6)
    }

    @Test func tablesAreComplete() {
        #expect(SpecialPurposeRange.ipv4.count == v4Cases.count)
        #expect(SpecialPurposeRange.ipv6.count == v6Cases.count)
    }

    @Test func publicAddressesHaveNoRange() {
        let texts = ["1.1.1.1", "8.8.8.8", "193.0.6.139", "172.15.0.1", "172.32.0.1", "100.128.0.1", "198.20.0.1",
                     "2001:4860:4860::8888", "2606:4700:4700::1111", "2001:67c:2e8:22::c100:696", "2400::1"]
        for text in texts {
            #expect(ip(text).specialPurpose == nil, Comment(rawValue: text))
        }
    }

    @Test func broadcastIsMoreSpecificThanReserved() {
        #expect(ip("255.255.255.255").specialPurpose?.kind == .broadcast)
        #expect(ip("255.255.255.254").specialPurpose?.kind == .reserved)
    }

    @Test func containingPrefixes() {
        #expect(SpecialPurposeRange.containing(ip("10.0.0.0"), length: 8)?.cidr == "10.0.0.0/8")
        #expect(SpecialPurposeRange.containing(ip("10.1.0.0"), length: 16)?.cidr == "10.0.0.0/8")
        // A prefix shorter than the range is not inside it.
        #expect(SpecialPurposeRange.containing(ip("10.0.0.0"), length: 7) == nil)
        #expect(SpecialPurposeRange.containing(ip("172.0.0.0"), length: 8) == nil)
        #expect(SpecialPurposeRange.containing(ip("2001:db8:1::"), length: 48)?.cidr == "2001:db8::/32")
        #expect(SpecialPurposeRange.containing(ip("2001:db8::"), length: 31) == nil)
    }

    @Test func fieldsAndProbing() throws {
        let rfc1918 = try #require(ip("192.168.1.1").specialPurpose)
        #expect(rfc1918.name == "Private use")
        #expect(rfc1918.rfc == "RFC 1918")
        #expect(rfc1918.cidr == "192.168.0.0/16")
        let allowed: Set<SpecialPurposeRange.Kind> = [.privateUse, .sharedCGNAT, .linkLocal, .loopback, .uniqueLocal]
        for range in SpecialPurposeRange.ipv4 + SpecialPurposeRange.ipv6 {
            #expect(range.allowsProbing == allowed.contains(range.kind), Comment(rawValue: range.cidr))
        }
        #expect(ip("100.72.13.5").specialPurpose?.kind == .sharedCGNAT)
    }

    @Test func tableNetworksAreAligned() {
        for range in SpecialPurposeRange.ipv4 + SpecialPurposeRange.ipv6 {
            #expect(range.network.masked(to: range.length) == range.network, Comment(rawValue: range.cidr))
        }
    }

    // MARK: embedded IPv4

    @Test func embeddedIPv4() {
        #expect(ip("::ffff:8.8.8.8").embeddedIPv4 == ip("8.8.8.8"))
        #expect(ip("::ffff:808:808").embeddedIPv4 == ip("8.8.8.8"))
        #expect(ip("64:ff9b::808:808").embeddedIPv4 == ip("8.8.8.8"))
        #expect(ip("2002:808:808::").embeddedIPv4 == ip("8.8.8.8"))
        #expect(ip("2002:808:808:1:2:3:4:5").embeddedIPv4 == ip("8.8.8.8"))
        #expect(ip("8.8.8.8").embeddedIPv4 == nil)
        #expect(ip("2001:4860:4860::8888").embeddedIPv4 == nil)
        #expect(ip("64:ff9b:1::808:808").embeddedIPv4 == nil)
        #expect(ip("::8.8.8.8").embeddedIPv4 == nil)   // IPv4-compatible is deprecated, not offered
    }

    // MARK: masked

    @Test func maskedClearsHostBits() {
        #expect(ip("1.1.1.7").masked(to: 24) == ip("1.1.1.0"))
        #expect(ip("1.1.1.7").masked(to: 32) == ip("1.1.1.7"))
        #expect(ip("1.1.1.7").masked(to: 0) == ip("0.0.0.0"))
        #expect(ip("172.31.255.255").masked(to: 12) == ip("172.16.0.0"))
        #expect(ip("10.255.0.1").masked(to: 9) == ip("10.128.0.0"))
        #expect(ip("2001:db8:ffff::1").masked(to: 32) == ip("2001:db8::"))
        #expect(ip("2001:db8:ffff::1").masked(to: 36) == ip("2001:db8:f000::"))
        #expect(ip("2001:db8::1").masked(to: 128) == ip("2001:db8::1"))
        #expect(ip("2001:db8::1").masked(to: 0) == ip("::"))
        #expect(ip("1.2.3.4").masked(to: 99) == ip("1.2.3.4"))
        #expect(ip("1.2.3.4").masked(to: -3) == ip("0.0.0.0"))
    }

    // MARK: ASNs

    @Test func reservedASNBoundaries() {
        let table: [(UInt32, String?, String?)] = [
            (0, "Reserved", "RFC 7607"),
            (1, nil, nil),
            (23455, nil, nil),
            (23456, "AS_TRANS", "RFC 6793"),
            (23457, nil, nil),
            (64495, nil, nil),
            (64496, "Documentation", "RFC 5398"),
            (64511, "Documentation", "RFC 5398"),
            (64512, "Private use", "RFC 6996"),
            (65534, "Private use", "RFC 6996"),
            (65535, "Reserved", "RFC 7300"),
            (65536, "Documentation", "RFC 5398"),
            (65551, "Documentation", "RFC 5398"),
            (65552, "Reserved by IANA", "IANA registry"),
            (131_071, "Reserved by IANA", "IANA registry"),
            (131_072, nil, nil),
            (13335, nil, nil),
            (4_199_999_999, nil, nil),
            (4_200_000_000, "Private use", "RFC 6996"),
            (4_294_967_294, "Private use", "RFC 6996"),
            (4_294_967_295, "Reserved", "RFC 7300"),
        ]
        for (asn, name, rfc) in table {
            let found = ReservedASN.lookup(asn)
            #expect(found?.name == name, Comment(rawValue: "AS\(asn)"))
            #expect(found?.rfc == rfc, Comment(rawValue: "AS\(asn)"))
        }
    }

    @Test func reservedASNBlocksAreDisjointAndAscending() {
        for (a, b) in zip(ReservedASN.all, ReservedASN.all.dropFirst()) {
            #expect(a.range.upperBound < b.range.lowerBound)
        }
    }
}
