// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct WhoisRangeTests {
    @Test func alignedRangesBecomeOneBlock() {
        #expect(WhoisSummarizer.cidrs(fromRange: "193.0.0.0 - 193.0.7.255") == ["193.0.0.0/21"])
        #expect(WhoisSummarizer.cidrs(fromRange: "8.8.8.0 - 8.8.8.255") == ["8.8.8.0/24"])
        #expect(WhoisSummarizer.cidrs(fromRange: "10.0.0.0 - 10.255.255.255") == ["10.0.0.0/8"])
        #expect(WhoisSummarizer.cidrs(fromRange: "1.2.3.4 - 1.2.3.4") == ["1.2.3.4/32"])
        #expect(WhoisSummarizer.cidrs(fromRange: "0.0.0.0 - 255.255.255.255") == ["0.0.0.0/0"])
    }

    @Test func nonAlignedRangesUseTheMinimalCover() {
        #expect(WhoisSummarizer.cidrs(fromRange: "192.0.2.0 - 192.0.2.130") == [
            "192.0.2.0/25", "192.0.2.128/31", "192.0.2.130/32",
        ])
        #expect(WhoisSummarizer.cidrs(fromRange: "10.0.0.1 - 10.0.0.6") == [
            "10.0.0.1/32", "10.0.0.2/31", "10.0.0.4/31", "10.0.0.6/32",
        ])
        #expect(WhoisSummarizer.cidrs(fromRange: "193.0.4.0 - 193.0.9.255") == ["193.0.4.0/22", "193.0.8.0/23"])
        #expect(WhoisSummarizer.cidrs(fromRange: "255.255.255.254 - 255.255.255.255") == ["255.255.255.254/31"])
        #expect(WhoisSummarizer.cidrs(fromRange: "1.0.0.255 - 1.0.1.0") == ["1.0.0.255/32", "1.0.1.0/32"])
    }

    @Test func ipv6Ranges() {
        #expect(WhoisSummarizer.cidrs(fromRange: "2001:4800:: - 2001:49FF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF") == ["2001:4800::/23"])
        #expect(WhoisSummarizer.cidrs(fromRange: "2001:db8:: - 2001:db8::ffff") == ["2001:db8::/112"])
        #expect(WhoisSummarizer.cidrs(fromRange: "2001:db8::1 - 2001:db8::4") == [
            "2001:db8::1/128", "2001:db8::2/127", "2001:db8::4/128",
        ])
        #expect(WhoisSummarizer.cidrs(fromRange: ":: - ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff") == ["::/0"])
    }

    @Test func cidrInputIsNormalised() {
        #expect(WhoisSummarizer.cidrs(fromRange: "193.0.0.0/21") == ["193.0.0.0/21"])
        #expect(WhoisSummarizer.cidrs(fromRange: "193.0.3.7/21") == ["193.0.0.0/21"])
        #expect(WhoisSummarizer.cidrs(fromRange: "2001:DB8::/32") == ["2001:db8::/32"])
    }

    @Test func invalidInputGivesNothing() {
        #expect(WhoisSummarizer.cidrs(fromRange: "").isEmpty)
        #expect(WhoisSummarizer.cidrs(fromRange: "garbage").isEmpty)
        #expect(WhoisSummarizer.cidrs(fromRange: "10.0.0.9 - 10.0.0.1").isEmpty)           // reversed
        #expect(WhoisSummarizer.cidrs(fromRange: "10.0.0.1 - 2001:db8::1").isEmpty)        // mixed families
        #expect(WhoisSummarizer.cidrs(fromRange: "10.0.0.0/33").isEmpty)
        #expect(WhoisSummarizer.cidrs(fromRange: "10.0.0.0/x").isEmpty)
    }

    @Test func rangeFromCIDR() {
        #expect(WhoisRange.range(fromCIDR: "193.0.0.0/21") == "193.0.0.0 - 193.0.7.255")
        #expect(WhoisRange.range(fromCIDR: "1.2.3.4/32") == "1.2.3.4 - 1.2.3.4")
        #expect(WhoisRange.range(fromCIDR: "2001:4860::/32") == "2001:4860:: - 2001:4860:ffff:ffff:ffff:ffff:ffff:ffff")
        #expect(WhoisRange.range(fromCIDR: "0.0.0.0/0") == "0.0.0.0 - 255.255.255.255")
        #expect(WhoisRange.range(fromCIDR: "nope") == nil)
    }

    @Test func prefixLengths() {
        #expect(WhoisRange.prefixLength(of: "8.8.8.0/24") == 24)
        #expect(WhoisRange.prefixLength(of: "8.8.8.0 - 8.8.8.255") == 24)
        #expect(WhoisRange.prefixLength(of: "193.0.4.0 - 193.0.9.255") == 20)
        #expect(WhoisRange.prefixLength(of: "2001:4800:: - 2001:49FF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF") == 23)
        #expect(WhoisRange.prefixLength(of: "1.2.3.4 - 1.2.3.4") == 32)
        #expect(WhoisRange.prefixLength(of: "nope") == nil)
    }

    @Test func routeCoverage() throws {
        let prefix = try #require(WhoisRange.parseCIDR("193.0.0.0/21"))
        #expect(WhoisRange.route("193.0.0.0/21", covers: prefix))
        #expect(WhoisRange.route("193.0.0.0/16", covers: prefix))
        #expect(!WhoisRange.route("193.0.0.0/24", covers: prefix))
        #expect(!WhoisRange.route("194.0.0.0/8", covers: prefix))
        #expect(!WhoisRange.route("2001:db8::/32", covers: prefix))
        #expect(!WhoisRange.route("junk", covers: prefix))
    }

    @Test func addressFormatting() throws {
        #expect(WhoisRange.parseAddress("2001:0DB8:0:0:0:0:0:1").map(WhoisRange.format) == "2001:db8::1")
        #expect(WhoisRange.parseAddress(" 1.2.3.4 ").map(WhoisRange.format) == "1.2.3.4")
        #expect(WhoisRange.parseAddress("x") == nil)
        #expect(WhoisRange.format([1, 2, 3]) == "")
    }
}
