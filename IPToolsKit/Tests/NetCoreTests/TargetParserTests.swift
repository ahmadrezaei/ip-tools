// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Testing
@testable import NetCore

@Suite struct TargetParserTests {
    private func ip(_ s: String) -> Target { .ip(IPAddress(s)!) }

    @Test(arguments: [
        ("1.1.1.1", "ip:1.1.1.1"),
        ("  1.1.1.1  ", "ip:1.1.1.1"),
        ("1.1.1.1:53", "ip:1.1.1.1"),
        ("https://1.1.1.1/dns-query", "ip:1.1.1.1"),
        ("2606:4700:4700::1111", "ip:2606:4700:4700::1111"),
        ("[2606:4700:4700::1111]", "ip:2606:4700:4700::1111"),
        ("[::1]:8080", "ip:::1"),
        ("fe80::1%en0", "ip:fe80::1"),
        ("apple.com", "host:apple.com"),
        ("Apple.COM", "host:Apple.COM"),
        ("apple.com.", "host:apple.com"),
        ("https://www.apple.com/iphone?x=1#top", "host:www.apple.com"),
        ("http://user:pw@example.org:8443/path", "host:example.org"),
        ("example.org:443", "host:example.org"),
        ("localhost", "host:localhost"),
        ("my_host.local", "host:my_host.local"),
        ("1.1.1.0/24", "ip:1.1.1.0"),
        ("", "nil"),
        ("   ", "nil"),
        ("not a host", "nil"),
        ("1.2.3", "nil"),
        ("1.1.1.256", "nil"),
        ("-bad.com", "nil"),
        ("bad..com", "nil"),
        ("ex ample.com", "nil"),
        ("host:abc", "nil"),
        ("[::1", "nil"),
        ("[1.1.1.1]", "nil"),
    ]) func hostMode(input: String, expected: String) {
        let result = TargetParser.parse(input, mode: .host)
        let described: String
        switch result {
        case let .ip(a)?: described = "ip:\(a)"
        case let .hostname(h)?: described = "host:\(h)"
        case nil: described = "nil"
        default: described = "unexpected"
        }
        #expect(described == expected)
    }

    @Test func bgpMode() {
        #expect(TargetParser.parse("AS13335", mode: .bgp) == .asn(13335))
        #expect(TargetParser.parse("as13335", mode: .bgp) == .asn(13335))
        #expect(TargetParser.parse(" 13335 ", mode: .bgp) == .asn(13335))
        #expect(TargetParser.parse("ASx", mode: .bgp) == .hostname("ASx"))
        #expect(TargetParser.parse("AS4294967296", mode: .bgp) == nil)
        #expect(TargetParser.parse("1.1.1.0/24", mode: .bgp) == .prefix(IPAddress("1.1.1.0")!, length: 24))
        #expect(TargetParser.parse("2606:4700::/32", mode: .bgp) == .prefix(IPAddress("2606:4700::")!, length: 32))
        #expect(TargetParser.parse("1.1.1.0/33", mode: .bgp) == ip("1.1.1.0"))
        #expect(TargetParser.parse("1.1.1.1", mode: .bgp) == ip("1.1.1.1"))
        #expect(TargetParser.parse("cloudflare.com", mode: .bgp) == .hostname("cloudflare.com"))
    }

    @Test func hostModeNeverReturnsBGPTargets() {
        #expect(TargetParser.parse("AS13335", mode: .host) == .hostname("AS13335"))
        #expect(TargetParser.parse("13335", mode: .host) == nil)
    }

    @Test func normalized() {
        #expect(TargetParser.normalized("  Apple.COM ") == "apple.com")
    }
}

@Suite struct ResolverTests {
    @Test func literalsResolveImmediately() async throws {
        let t = try await Resolver.resolve(" 1.1.1.1 ", preference: .ipv6)
        #expect(t.address.description == "1.1.1.1")
        #expect(t.hostname == nil)
        #expect(t.input == "1.1.1.1")
    }

    @Test func localhostResolves() async throws {
        let t = try await Resolver.resolve("localhost", preference: .ipv4)
        #expect(t.address.family == .v4)
        #expect(t.hostname == "localhost")
        #expect(!t.allAddresses.isEmpty)
    }

    @Test func invalidInputThrows() async {
        await #expect(throws: NetError.invalidTarget("not a host")) {
            _ = try await Resolver.resolve("not a host", preference: .automatic)
        }
    }

    @Test func unresolvableHostThrows() async {
        do {
            _ = try await Resolver.resolve("nonexistent.invalid", preference: .automatic)
            Issue.record("expected failure")
        } catch let error as NetError {
            if case .resolutionFailed = error {} else { Issue.record("wrong error \(error)") }
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func reverseNameTimesOutOrFails() async {
        let start = ContinuousClock.now
        _ = await Resolver.reverseName(for: IPAddress("192.0.2.1")!, timeout: .milliseconds(300))
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}
